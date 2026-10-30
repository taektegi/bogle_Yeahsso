// Figma 299:4379 / 437:2603. Use native PNG exports: SVG renderers interpret
// the translucent inner-shadow filter differently (filled vs hollow centre).
// Run: NODE_PATH=<directory containing sharp> node tool/generate_loading_bubbles.cjs
const path = require('node:path');
const sharp = require('sharp');

async function main() {
  const assets = path.resolve(__dirname, '../assets/figma');
  const sources = path.resolve(__dirname, 'assets/loading_bubbles');
  // Figma has two coincident beige layers: retain both as one tappable bubble.
  const groups = [[0], [1, 2], [3], [4], [5], [6], [7], [8]];
  for (const [index, layers] of groups.entries()) {
    const images = await Promise.all(layers.map(layer =>
      sharp(path.join(sources, `layer_${layer}.png`)).png().toBuffer()
    ));
    let rendered = sharp(images[0]);
    if (images.length > 1) rendered = rendered.composite(images.slice(1).map(input => ({ input })));
    await rendered.png().toFile(path.join(assets, `generation_bubble_${index}.png`));
  }
  console.log('Rendered 8 generation-only bubbles from 9 native Figma PNG exports.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
