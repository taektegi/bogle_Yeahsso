# Character-generation loading bubbles

Source: Figma `bwWLmNFUlLdF4TTO6QlYR7`, frame `299:4379`, group `437:2603`.
Exported with `exportAsync({format: 'PNG', contentsOnly: true,
useAbsoluteBounds: true, constraint: {type: 'SCALE', value: 3}})`.
These are transparent individual assets, not screen captures. Rotation is
already included. Native exports preserve Figma's translucent inner shadow;
SVG conversion incorrectly fills the centre with colour.

| Source | Node | Output bubble |
| --- | --- | --- |
| layer_0.png | 437:2604 | 0: yellow |
| layer_1.png + layer_2.png | 437:2608 + 437:2612 | 1: beige (coincident layers) |
| layer_3.png | 437:2616 | 2: large cyan |
| layer_4.png | 437:2620 | 3: lavender |
| layer_5.png | 437:2624 | 4: small cyan |
| layer_6.png | 437:2628 | 5: lime |
| layer_7.png | 437:2632 | 6: coral |
| layer_8.png | 437:2636 | 7: mint |

`tool/generate_loading_bubbles.cjs` creates the eight runtime images from
these nine layers. Home, startup, and the bubble minigame keep their own assets.
