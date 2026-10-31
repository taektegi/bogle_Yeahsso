-- 사용자 결정: 기존 말투 세 가지와 앱의 느낌·높임 조합 여덟 가지를 함께 허용한다.
alter table public.friends drop constraint friends_speech_style_check;
alter table public.friends add constraint friends_speech_style_check
    check (speech_style in (
        '~지요!', '해요체', '반말',
        'plain_casual', 'plain_polite',
        'bouncy_casual', 'bouncy_polite',
        'story_casual', 'story_polite',
        'robot_casual', 'robot_polite'
    ));
