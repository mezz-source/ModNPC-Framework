# Preview rendering

How the Preview box turns a tagged line into letters that type out one by one, shake, wave and blip, and why it is built that way.

- [The short version](#the-short-version)
- [Why not a text widget](#why-not-a-text-widget)
- [The pipeline](#the-pipeline)
- [Time is the only state](#time-is-the-only-state)
- [The timeline: when each letter appears](#the-timeline-when-each-letter-appears)
- [Layout: where each letter sits](#layout-where-each-letter-sits)
- [The update loop](#the-update-loop)
- [Drawing a frame](#drawing-a-frame)
- [Effects](#effects)
- [Things that happen once: blips and instant tags](#things-that-happen-once-blips-and-instant-tags)
- [The typing blip](#the-typing-blip)
- [Tuning](#tuning)
- [Differences from the game](#differences-from-the-game)
- [Where the code lives](#where-the-code-lives)

---

## The short version

When Play is pressed (or Enter in the format box), the line is worked out **once**: which letters it has, how each is styled, **when** each appears and **where** each sits. After that, a timer ticks about 60 times a second. Each tick reads the clock into one variable, `time` (seconds since Play), and redraws. Everything on screen is computed from `time`: which letters are visible, how faded in they are, how far they have shaken or bobbed. Nothing accumulates frame to frame.

## Why not a text widget

The format box is a `QPlainTextEdit`, and an earlier version of the preview was a `QTextBrowser`. Stock text widgets can do bold, italic, color and wrapping, but they lay out and paint whole runs of text at once. The preview needs things they can't do:

- each letter moving on its own (shake, wave)
- letters appearing one at a time on a schedule (`<speed>`, `<pause>`)
- a new letter fading in while the rest stay still

So the preview is a plain `QWidget` that paints every letter itself with `QPainter.drawText`, one call per letter, at a position it chose.

## The pipeline

```
format box text
      |
      v
  parse()            markup/resolver.py   letters + style, instant tags        (once per Play)
      |
      +--> build_timeline()  markup/timeline.py   reveal time per letter,       (once per Play)
      |                                           time per instant tag
      +--> build_layout()    markup/layout.py     x and line per letter         (once per Play / resize)
      |
      v
  PreviewWidget      gui/preview.py       every tick: time -> what to draw     (~60x a second)
```

`parse`, `build_timeline` and `build_layout` are plain Python with no Qt widgets, so they are unit tested on their own (`tests/test_markup.py`, `tests/test_preview_timing.py`). The widget only has to answer one question each frame: *given `time`, what does the line look like?*

## Time is the only state

The core decision: **the preview is a function of time**, not a simulation that steps forward.

A typical typewriter is written as "every tick, show one more letter" or "every tick, add `dt` to a counter and move each letter a bit". This one isn't. Instead:

- Every letter gets a **reveal time** up front (see the next section).
- Each frame reads `time` from a `QElapsedTimer` (the real clock), not by adding up timer intervals.
- A letter is visible if `time >= reveal[i]`. Its fade, shake and wave are formulas of `time` and its index.

Why:

- **Frame rate doesn't matter.** `QTimer` ticks are not exact; on a busy machine a tick can arrive late or be skipped. A counter-based typewriter would then type slower. Here a late frame just shows the line a little further along, exactly where it should be.
- **No drift.** Reading the clock each frame means errors don't add up over a long line. Summing 16 ms ticks would.
- **Replay is trivial.** Play restarts the clock at 0. There is no per-letter state to reset.
- **It is testable.** "When does letter 7 appear?" is a list lookup, checked in tests without running a GUI.
- **Room to grow.** Because frames depend only on `time`, a scrub bar, pause/resume or slow motion would only change how `time` is computed, not the drawing code.

The only state that moves forward on its own is two cursors for things that must happen exactly once (blips, instant tags), covered [below](#things-that-happen-once-blips-and-instant-tags).

## The timeline: when each letter appears

`build_timeline` (`markup/timeline.py`) walks the parsed letters with a running clock `t`, starting at 0:

| Thing | Effect on `t` |
|---|---|
| Any letter | Appears at `t`, then `t += 1 / (chars_per_second * speed)` |
| `<speed=N>` | Sets `speed` for the letters inside it: 2 = half the time per letter |
| `<pause=S>` | Fires at `t`, then `t += S` |
| `<sfx>`, `<event>`, `<anim>`, `<stopanim>` | Fire at `t`; take no time |

The base rate is `DEFAULT_CHARS_PER_SECOND = 30` (set on the widget as `chars_per_second`).

Details that follow from the markup rules:

- **Instant tags fire before the next letter**, in the order written. In `Wait.<pause=1><sfx=Gasp> What?` the pause fires after the `.`, then the sfx fires once the pause is over, then the space types.
- **Tags at the very end** fire after the last letter, and count toward the line's `duration`.
- **Every character takes time,** including spaces and punctuation. Punctuation does *not* add an automatic delay; a writer who wants a beat after a comma adds `<pause>`. This keeps the timing exactly what the markup says, with no hidden rules.

The result is a `Timeline`: `reveal[i]` for every letter, a time for every instant tag, and the total `duration`.

## Layout: where each letter sits

`build_layout` (`markup/layout.py`) gives each letter an `x` and a line number, following the game's `Layout.build`:

- Lines break at newlines, after spaces and after hyphens.
- A word too long for a whole line breaks between letters.
- Trailing spaces may hang past the edge and are ignored when centering.
- Lines are centered by default.

Decisions:

- **The whole line is laid out before typing starts.** A letter's spot is fixed from the first frame, so text never jumps or re-wraps as it types. A word that will wrap starts on its new line rather than starting at the end of one line and jumping down.
- **Width measuring is passed in.** Layout takes a `measure(char)` function instead of a font, so it has no Qt dependency and tests can use "every letter is 1 wide". The widget passes one built on `QFontMetricsF`, using the bold/italic font variant for each letter, since those are the styles that change width.
- **Letters are measured one at a time.** That drops kerning between letter pairs, but every letter needs its own position to move on its own, and the game places one label per letter too.
- **Layout is cached.** It is rebuilt only when the text changes or the widget is resized, not every frame.

## The update loop

```python
self._timer = QTimer(self)          # ~60 fps (FRAME_MS = 16), PreciseTimer
self._timer.timeout.connect(self._tick)

def _tick(self):
    self._time = self._clock.elapsed() / 1000.0   # the time variable
    ... fire blips and instant tags whose time has passed ...
    ... stop the timer if nothing is moving any more ...
    self.update()                                  # schedule paintEvent
```

- **`play()`** resets `time` and the cursors, restarts the clock and starts the timer.
- **The tick doesn't draw.** It updates `time`, handles one-off events, and asks Qt to repaint. Qt then calls `paintEvent`, which does the drawing.
- **The loop stops itself when idle.** Once typing has finished, the last letter has faded in and no tag labels are showing, the timer stops and the last frame stays on screen. A line with shake or wave keeps the timer running, because those effects never end. This keeps CPU use at zero for a finished, still line.

## Drawing a frame

`paintEvent` fills the background, then for each placed letter, in typing order:

1. `age = time - reveal[i]`. If `age < 0`, the letter hasn't been typed yet, and neither has anything after it (reveal times only go up), so the loop stops.
2. Spaces are skipped. They have a position but nothing to draw.
3. **Fade-in:** `fade = min(1, age / FADE_IN)` sets the letter's opacity, and the letter starts `RISE` pixels low and slides up as it fades. This makes new letters easier to follow than a hard pop.
4. Effect offsets are added (next section).
5. The letter is drawn in its own font (bold/italic) and color (its `<color>`, or the palette's text color for the default) at `layout position + offsets`.

The block of lines is centered vertically in the box. Every line uses the bold font's height, so mixing bold and plain text doesn't make lines uneven.

On top of the text, a thin progress bar along the bottom shows `time / duration`, and fired instant tags are listed in the bottom-left corner.

## Effects

Effects only **add an offset** to a letter's laid-out position. They never change the layout, so a shaking word can't push its neighbors around or change wrapping. Offsets from different effects add together, which is how `<shake><wave>` gives a letter that does both.

### Wave

```
dy -= sin(time * WAVE_HZ * 2π - index * WAVE_PHASE) * WAVE_PIXELS * intensity
```

A sine of time, shifted by the letter's index so neighbors are a step behind each other, which is what makes it read as a wave travelling along the text. Being a pure function of `time` and `index`, it is smooth at any frame rate.

### Shake

```
frame = floor(time * SHAKE_RATE)
dx += noise(index, frame, 0) * SHAKE_PIXELS * intensity
dy += noise(index, frame, 1) * SHAKE_PIXELS * intensity
```

Shake is random jitter, but it is **not** a call to `random()` each paint:

- **`noise` is a hash, not a random number generator.** The same `(index, frame, axis)` always gives the same value in [-1, 1]. No random state is stored, and a repaint for any other reason (resize, a tag label fading) draws the same shake position, instead of jittering extra.
- **Shake runs at its own rate.** `frame` steps `SHAKE_RATE` (24) times a second, whatever the screen refresh is. Changing the frame rate doesn't change how fast letters shake, and 24 reads as a nervous jitter rather than a 60 Hz blur.
- **Each letter shakes on its own** because `index` goes into the hash, as the markup describes.

### Intensity

`<shake=2>` and `<wave=2>` multiply the pixel size of the effect. Intensity doesn't change speed.

## Things that happen once: blips and instant tags

Drawing can be recomputed from `time` at any moment, but a sound or a "tag fired" label must happen **exactly once**, at the right moment. For those the widget keeps two cursors:

- `_next_char`: the next letter that hasn't been typed yet
- `_next_event`: the next instant tag that hasn't fired yet

Each tick, both cursors move forward over **everything whose time has passed since the last tick**:

```python
while next_char < len(reveal) and reveal[next_char] <= time:
    ...  # this letter was just typed
    next_char += 1
```

This is the "catch up" pattern: if a tick arrives late and three letters came due in that gap, all three are handled, none are skipped. `play()` resets both cursors to 0.

Fired instant tags show as labels (`pause 0.6s`, `sfx: Blip`, `event: Done`, ...) in the bottom-left corner, fading out over `FLASH_SECONDS`. This shows *when* a tag fires without needing the sounds, events or animations themselves.

## The typing blip

The preview plays a short sound as letters type, like the voice blips in many games.

- **Only letters and digits blip.** `is_blip_letter` checks the Unicode category of the letter's first code point: letters (`L*`) and digits (`N*`) blip; spaces, punctuation, symbols and emoji don't. Accented letters count as letters. Silent punctuation keeps the blips matching the spoken rhythm of the words.
- **At most one blip per frame.** If several letters come due in one tick (high `<speed>`, or a late frame), the widget emits `letterTyped` once. Overlapping blips would cut each other off anyway (next point), so more would be inaudible.
- **The blip never overlaps itself.** `BlipPlayer.play()` (`gui/sound.py`) stops the sound if it is still playing, then starts it again from the beginning. With a 0.14 s blip and a letter every 0.033 s at normal speed, nearly every blip cuts off the one before it. This gives the clipped, chattery sound wanted, rather than a building wash of overlapping copies.
- **The widget doesn't know about audio.** It emits `letterTyped`; the window connects that to the blip player. The preview stays testable without sound, and a different voice per character could swap the player without touching the drawing code.
- **`QSoundEffect`** is used because it is made for short, low-latency UI sounds. It plays only uncompressed WAV, so the Blip Sound browse dialog (Sound tab) only offers `.wav`. The default sound is `assets/sounds/default_blip.wav`.

## Tuning

All feel-related numbers are constants at the top of `gui/preview.py` (and `markup/timeline.py`, `gui/sound.py`):

| Constant | Default | Controls |
|---|---|---|
| `DEFAULT_CHARS_PER_SECOND` | 30 | Base typing speed |
| `FRAME_MS` | 16 | Update loop interval (~60 fps) |
| `FADE_IN` | 0.08 s | How long a new letter takes to fade in |
| `RISE` | 4 px | How far a new letter slides up while fading in |
| `SHAKE_PIXELS` | 1.5 px | Shake distance at intensity 1 |
| `SHAKE_RATE` | 24 /s | How often shake picks a new offset |
| `WAVE_PIXELS` | 3 px | Wave height at intensity 1 |
| `WAVE_HZ` | 1.2 | Wave bobs per second |
| `WAVE_PHASE` | 0.6 rad | Wave offset between neighboring letters |
| `FLASH_SECONDS` | 1.4 s | How long a fired-tag label stays |
| `BLIP_VOLUME` | 0.6 | Blip volume (0-1) |

## Differences from the game

The preview shows how tags **behave**, not a pixel-exact copy of the game:

- It uses the app's font, not the game's, so letter widths and wrapping points differ.
- Shake and wave sizes, wave speed and the base typing speed are this app's guesses; the game's Presenter (which will do the typing in game) isn't built yet. When it is, these constants should be matched to it.
- `<sfx>`, `<event>`, `<anim>` and `<stopanim>` only show as labels; they don't play sounds or animations.
- Letters are drawn without kerning between pairs (the game also places letters one by one).

## Where the code lives

| File | Role |
|---|---|
| `src/markup/resolver.py` | `parse()`: tagged text → styled letters + instant tags |
| `src/markup/timeline.py` | `build_timeline()`: reveal time per letter, time per instant tag |
| `src/markup/layout.py` | `build_layout()`: wrapping, centering, x per letter |
| `src/gui/preview.py` | `PreviewWidget`: update loop, `time`, drawing, effects, `letterTyped` |
| `src/gui/sound.py` | `BlipPlayer`: restart-don't-overlap blip |
| `src/gui/text_writer_gui.py` | Play button / Enter → `set_markup(format text)`; blip wiring; Blip Sound picker |
| `tests/test_preview_timing.py` | Timeline, layout and blip-letter tests |
