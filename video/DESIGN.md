# DemoBench video — design

Derived from the live site (`web/index.html`, dark theme). Brand truth for every scene.

## Style Prompt

A calm, precise showcase in the DemoBench house style: a dark warm-graphite room, flat
interface chrome with hairline rules and square corners, chunky 12× pixel footage from the
160×120 machine, and one hot orange accent. Type does the talking: a wide heavy display face
for names, a friendly grotesque for plain-language sentences, and a monospace for machine
facts. Motion follows the music (128 BPM, cuts on 4-bar downbeats with a short white flash,
the way the demos cut their own scenes).

## Colors

| Role | Hex | Use |
|---|---|---|
| room | `#151619` | canvas, panels |
| deep | `#0c0d0f` | behind footage, letterbox |
| ink | `#efeee9` | headlines, body |
| mid | `#a3a19a` | secondary text, labels |
| line | `#3a3b41` | hairlines, empty gauge cells |
| accent | `#ff5a36` | one focal hit per scene: gauge fill, index numbers, scope trace |
| gpu | `#2aa39d` | GPU tag only |
| spu | `#8b6cf0` | SPU tag only |

## Typography

- **Unbounded** 800 (600 for small caps labels) — demo names, headlines, logotype. Tracking −0.04em.
- **Figtree** 400/500 — sentences in plain language. 34–40px.
- **Red Hat Mono** 400/500 — byte counts, instruction listings, spec rows, frame counters. `tabular-nums`.

## Motion

- Cuts land on 4-bar downbeats (every 7.5 s) with a 0.3 s white flash (`expo.out` decay).
- Entrances: masked rise for display type (`expo.out`), waterfall for mono labels (`power3.out`),
  gauge cells fill in a ≤0.5 s stagger (`power2.out`), hairlines draw with `scaleX` (`power4.inOut`).
- One ambient motion per scene. Beat = 0.46875 s.

## What NOT to Do

- No rounded pills, cards inside cards, drop shadows or glassmorphism: flat panels and hairlines.
- No gradient text, no neon glows, no purple-to-blue gradients.
- Never smooth or filter the demo footage: pixels stay square and crisp (nearest-neighbour only).
- No marketing superlatives ("revolutionary", "next-gen"). Plain sentences, concrete numbers.
- No text smaller than 20px; no more than ~25 words on screen per scene.
