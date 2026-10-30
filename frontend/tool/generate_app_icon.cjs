// Build native iOS icons from the original Figma bubble and cream wordmark.
// Figma bwWLmNFUlLdF4TTO6QlYR7: 585:2438 (tile), 585:2446 (bubble),
// 585:2439 (wordmark). Preserve the vectors and their original filter effects.
// The tile is square/opaque; iPadOS applies its own rounded icon mask.
// Run: NODE_PATH=<path containing sharp and @resvg/resvg-js> node tool/generate_app_icon.cjs
const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');
const { Resvg } = require('@resvg/resvg-js');

const masterSize = 1024;
const designSize = 497;
const tileColor = '#8BA2FF';

async function layer(root, filename, slot) {
  const source = fs.readFileSync(path.join(root, 'assets/app_icon', filename));
  // Use Figma's transparent bubble export: external SVG renderers disagree
  // with Figma on the inner shadow of the translucent (33% opacity) circle.
  const rendered = filename.endsWith('.png') ? source : new Resvg(source, {
    fitTo: { mode: 'zoom', value: masterSize / designSize },
    font: { loadSystemFonts: false },
  }).render().asPng();
  return {
    input: await sharp(rendered).resize(
      Math.round(slot.width * masterSize / designSize),
      Math.round(slot.height * masterSize / designSize),
      { fit: 'fill' },
    ).png().toBuffer(),
    left: Math.round(slot.x * masterSize / designSize),
    top: Math.round(slot.y * masterSize / designSize),
  };
}

async function main() {
  const root = path.resolve(__dirname, '..');
  const folder = path.join(root, 'ios/Runner/Assets.xcassets/AppIcon.appiconset');
  const layers = await Promise.all([
    layer(root, 'bubble.png', {
      // The exported render already includes the Figma group's 90° rotation.
      x: 0.297, y: 0, width: 496.70275, height: 496.70275,
    }),
    layer(root, 'wordmark.svg', {
      x: 53, y: 127, width: 391.35254, height: 242.17337,
    }),
  ]);
  const png = await sharp({ create: {
    width: masterSize, height: masterSize, channels: 3, background: tileColor,
  } }).composite(layers).removeAlpha().png().toBuffer();
  const manifest = JSON.parse(fs.readFileSync(path.join(folder, 'Contents.json')));
  const sizes = new Map(manifest.images.map(i => [i.filename, Math.round(parseFloat(i.size) * parseFloat(i.scale))]));
  for (const [filename, pixels] of sizes) {
    await sharp(png).resize(pixels, pixels).removeAlpha().png().toFile(path.join(folder, filename));
  }
  for (const [filename, pixels] of sizes) {
    const info = await sharp(path.join(folder, filename)).metadata();
    if (info.width !== pixels || info.height !== pixels || info.hasAlpha) throw new Error(`Invalid icon: ${filename}`);
  }
  console.log(`Validated ${sizes.size} opaque PNGs; master: ${path.join(folder, 'Icon-App-1024x1024@1x.png')}`);
}
main().catch(error => { console.error(error); process.exitCode = 1; });
