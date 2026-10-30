import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../theme/bogle_theme.dart';

class PostcodeAddress {
  const PostcodeAddress({required this.zip, required this.street});
  final String zip, street;

  static PostcodeAddress? fromMessage(Object? value) {
    if (value is! Map || value['type'] != 'selected') return null;
    final zip = value['zip'], street = value['street'];
    if (zip is! String ||
        !RegExp(r'^\d{5}$').hasMatch(zip) ||
        street is! String ||
        street.trim().isEmpty ||
        street.length > 300) {
      return null;
    }
    return PostcodeAddress(zip: zip, street: street.trim());
  }
}

typedef AddressSearch = Future<PostcodeAddress?> Function(BuildContext context);

Future<PostcodeAddress?> searchPostcode(BuildContext context) =>
    Navigator.of(context).push<PostcodeAddress>(
      MaterialPageRoute(
        builder: (_) => const PostcodeSearchScreen(),
        fullscreenDialog: true,
      ),
    );

/// The official Kakao (formerly Daum) postcode UI, embedded instead of a popup.
/// Only the selected postcode/address crosses the bridge; recipient and phone
/// are entered in Flutter and never sent to this page.
class PostcodeSearchScreen extends StatefulWidget {
  const PostcodeSearchScreen({super.key, this.initialQuery = ''});
  final String initialQuery;
  @override
  State<PostcodeSearchScreen> createState() => _PostcodeSearchScreenState();
}

class _PostcodeSearchScreenState extends State<PostcodeSearchScreen> {
  WebViewController? _controller;
  Timer? _timeout;
  bool _ready = false, _failed = false, _selected = false;
  int? _resultCount;

  @visibleForTesting
  WebViewController? get debugController => _controller;
  @visibleForTesting
  int? get debugResultCount => _resultCount;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _timeout?.cancel();
    setState(() {
      _ready = false;
      _failed = false;
    });
    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..addJavaScriptChannel(
          'BoglePostcode',
          onMessageReceived: (message) {
            if (!mounted || _selected) return;
            try {
              final data = jsonDecode(message.message);
              if (data is! Map) return;
              final address = PostcodeAddress.fromMessage(data);
              if (address != null) {
                _selected = true;
                Navigator.of(context).pop(address);
              } else if (data['type'] == 'ready' || data['type'] == 'results') {
                _timeout?.cancel();
                setState(() {
                  _ready = true;
                  _failed = false;
                  if (data['count'] is int) _resultCount = data['count'] as int;
                });
              } else if (data['type'] == 'failed') {
                _fail();
              }
            } on FormatException {
              /* Ignore malformed third-party messages. */
            }
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              final uri = Uri.tryParse(request.url);
              if (request.url == 'about:blank') {
                return NavigationDecision.navigate;
              }
              final host = uri?.host ?? '';
              return uri?.scheme == 'https' &&
                      (host == 'kakao.com' ||
                          host.endsWith('.kakao.com') ||
                          host == 'daum.net' ||
                          host.endsWith('.daum.net'))
                  ? NavigationDecision.navigate
                  : NavigationDecision.prevent;
            },
            onWebResourceError: (error) {
              if (error.isForMainFrame == true) _fail();
            },
          ),
        );
      _controller = controller;
      _timeout = Timer(const Duration(seconds: 20), () {
        if (!_ready) _fail();
      });
      await controller.loadHtmlString(
        _html(widget.initialQuery),
        baseUrl: 'https://postcode.map.kakao.com/',
      );
      if (mounted) setState(() {});
    } catch (_) {
      _fail();
    }
  }

  void _fail() {
    if (mounted) setState(() => _failed = true);
    _timeout?.cancel();
  }

  @override
  void dispose() {
    _timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: BogleColors.cream,
    appBar: AppBar(
      title: const Text('주소 검색'),
      backgroundColor: BogleColors.cream,
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('도로명, 지번 또는 건물명으로 검색해 주세요.'),
              ),
              Expanded(
                child: Stack(
                  children: [
                    if (_controller != null && !_failed)
                      WebViewWidget(controller: _controller!),
                    if (!_ready && !_failed)
                      const Center(
                        child: CircularProgressIndicator(
                          semanticsLabel: '주소 검색 불러오는 중',
                        ),
                      ),
                    if (_failed)
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.wifi_off_rounded, size: 40),
                            const SizedBox(height: 16),
                            const Text(
                              '주소 검색에 연결하지 못했어요.\n인터넷 연결을 확인하고 다시 시도해 주세요.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: _load,
                              child: const Text('다시 시도'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  static String _html(String query) =>
      '''<!doctype html>
<html lang="ko"><head><meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body,#search{margin:0;width:100%;height:100%;background:#fff}body{overflow:hidden}</style>
</head><body><div id="search"></div><script>
function send(data){BoglePostcode.postMessage(JSON.stringify(data));}
function boot(){
 try {
  new kakao.Postcode({
   width:'100%',height:'100%',
   onresize:function(){send({type:'ready'});},
   onsearch:function(data){send({type:'results',count:data.count});},
   oncomplete:function(data){
    var street=data.userSelectedType==='R'?data.roadAddress:data.jibunAddress;
    if(!street)street=data.address;
    var extra=[];
    if(data.userSelectedType==='R'){
     if(data.bname&&/[동로가]\$/.test(data.bname))extra.push(data.bname);
     if(data.buildingName&&data.apartment==='Y')extra.push(data.buildingName);
    }
    if(extra.length)street+=' ('+extra.join(', ')+')';
    send({type:'selected',zip:data.zonecode,street:street});
   }
  }).embed(document.getElementById('search'),{q:${jsonEncode(query)},autoClose:false});
 }catch(e){send({type:'failed'});}
}
</script><script src="https://t1.kakaocdn.net/mapjsapi/bundle/postcode/prod/postcode.v2.js"
onload="boot()" onerror="send({type:'failed'})"></script></body></html>''';
}
