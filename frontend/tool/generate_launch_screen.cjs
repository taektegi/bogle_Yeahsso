// Rasterize original Figma layers, not a screenshot. Shared by iOS and Flutter
// to avoid a flash/jump during the native launch -> Flutter handoff.
// Run with the same sharp NODE_PATH as generate_app_icon.cjs.
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');

async function main() {
  const root = path.resolve(__dirname, '..');
  const assets = path.join(root, 'assets/figma');
  const folder = path.join(root, 'ios/Runner/Assets.xcassets/LaunchImage.imageset');
  const embed = (file, x, y, width, height) => {
    const data = fs.readFileSync(path.join(assets, file)).toString('base64');
    const mime = file.endsWith('.png') ? 'image/png' : 'image/svg+xml';
    return `<image x="${x}" y="${y}" width="${width}" height="${height}" href="data:${mime};base64,${data}"/>`;
  };
  // Logo only: the bubbles well up in Flutter right after launch, so the
  // first frame is the calm wordmark on cream (same spot as Figma 124:131).
  const layers = [embed('startup_wordmark.svg', 447, 324.629, 300, 185.644)];
  const source = Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="1194" height="834" viewBox="0 0 1194 834"><rect width="1194" height="834" fill="#FFFEEE"/>${layers.join('')}</svg>`);
  const master = await sharp(source, {density: 144}).flatten({background: '#FFFEEE'}).removeAlpha().png().toBuffer();
  fs.writeFileSync(path.join(assets, 'startup_scene.png'), master);
  for (const scale of [1, 2, 3]) {
    const filename = scale === 1 ? 'LaunchImage.png' : `LaunchImage@${scale}x.png`;
    await sharp(source, {density: 72 * scale}).flatten({background: '#FFFEEE'}).removeAlpha().png().toFile(path.join(folder, filename));
  }
  console.log('Generated shared 1194 × 834 startup composition and native launch scales.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
