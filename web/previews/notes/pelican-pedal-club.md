# Pelican Pedal Club

A self-contained DB32 beach ride: a white pelican in a coral cap pedals a turquoise bicycle past a palm tree and striped parasol. The camera arcs around the rider. Animated ocean normals reflect the three cloud ellipsoids and break the sun into a moving golden trail. Passing road markings, soft contact shading, sunlit feathers and stereo music complete the scene.

## Implementation

The renderer constructs perspective rays from a guest-computed camera basis. It solves transformed ellipsoid intersections analytically, clips the bicycle wheel ellipsoids into annuli, chooses the nearest hit, reconstructs its gradient normal and evaluates diffuse/specular lighting. A bounding sphere skips the bicycle/pelican intersection loop for background rays. The beach is an intersected plane with procedural sand and promenade markings. The ocean computes two wave-normal components, reflects the camera ray, intersects the distant cloud ellipsoids again, and evaluates a broad sun specular lobe. Thin crest highlights add fine moving detail. Contact shading is an analytic soft footprint; additional directional shadow rays intersect body and head proxies on the ground. Wheel cutouts test both quadratic roots to retain the far tire surface.

Fifty primitives include the bicycle, articulated legs and feet, pelican, passing palm/parasol, clouds and sun. Wheel and crank rotation is clockwise for travel along +X. Scenery and promenade marks move along -X. The palm and parasol travel at 1.25 world units per second and repeat over a 32-unit stretch, resetting only after clearing the entire camera orbit. Time comes from the VM's video frame counter.

The SPU computes 256 independent stereo sample frames per block at 48 kHz. Guest code implements polynomial oscillators, pluck envelopes, octave overtones, chord arpeggios, bass, a pitch-swept kick and deterministic noise percussion. A quiet stereo root/fifth pad adds sustained harmony; a guest-owned 85.3 ms cross-feedback delay adds space to the mix. The melody is a 32-step, 120 BPM loop; the camera repeats every 20 seconds.

RAM allocation:

| Region | Use |
|---|---|
| `0x10000..0x14aff` | 160×120 indexed page 0 |
| `0x15000..0x19aff` | 160×120 indexed page 1 |
| `0x1a000..0x1a7ff` | SPU stereo float output |
| `0x1a800..0x1aaff` | guest-generated 256-colour palette |
| `0x1b000..0x22fff` | guest stereo delay line |
| `0x24000..` | packed image: CPU, GPU, SPU, descriptors and note table |

GPU and SPU data bindings occupy disjoint RAM ranges. The CPU waits for completed rendering and a vblank before flipping the pages.

## Evidence

The latest kit validation report is `artifacts/wrap-check/report.json`. The full 60-second WASM audit is `artifacts/final/audit.json`, with spread-out frame captures and `audio.wav`. It measures render/animation dispatch work, SPU work, clipping, queue overruns, and conservative instruction counts. It also projects the VM's actual scenery bounds immediately before and after each reset, requiring two off-screen resets for each prop. `artifacts/scenery-frustum.json` independently checks the wrap endpoints against every camera pose in its 20-second orbit; the nearest conservative bound stays 20.7 pixels outside the image. The renderer's only loop has exactly 50 possible iterations. The audit records conservative instruction counts even though the former 8,192-instruction Studio cap has been lifted. The fixed GPU and SPU dispatch work budgets still apply.

Virtual machine time and measured browser throughput are separate. The reference capture verifies correctness for the tested interval; it does not establish 60 FPS playback.

Current build: **4,045 payload bytes**, plus the 32-byte DB32 header. The 3,600-frame WASM audit passed with no runtime faults, clipped PCM samples or audio queue overruns. Both scenery props reset twice; all four resets were outside the image, with the nearest actual bound 24.0 pixels beyond its edge. Peak render work was 917,128 ticks against a 1,048,576-tick budget; peak SPU work was 1,116 ticks against 65,536. Its audio peak was 0.7373. All reports and captures are in `artifacts/final`.

Browser verification is recorded in `artifacts/browser-playback.json` and `artifacts/player.jpg`. After about 73 seconds, the active graphics and audio synthesis backends were both WebGPU and the latest measured rate was 59.94 FPS. Audio output was muted during this scenery check. The player is left paused; **Resume** continues the ride, and **Sound on** enables music.
