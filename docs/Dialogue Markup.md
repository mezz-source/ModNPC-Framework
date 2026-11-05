# Dialogue Markup

Dialogue lines can carry tags that style parts of the text (color, bold, italic, shaking letters) and trigger things while the line is typed out (pauses, sounds). This guide covers every tag, how tags combine, and what happens to text the parser can't use.

- [Where lines come from](#where-lines-come-from)
- [Quick example](#quick-example)
- [Span tags](#span-tags)
- [Instant tags](#instant-tags)
- [Tag syntax rules](#tag-syntax-rules)
- [Combining tags](#combining-tags)
- [Escapes and special characters](#escapes-and-special-characters)
- [Broken tags](#broken-tags)
- [How a line gets on screen](#how-a-line-gets-on-screen)
- [What works today](#what-works-today)

---

## Where lines come from

A character's lines are `Dialog` instances in its Lines folder, grouped into category folders. The line's text is the `Dialog`'s `InitialPrompt`. Tags go straight into that text:

```
<Character Model>
  ModNPC/
    Lines/
      Greetings/        <- category (Folder)
        Hello           <- Dialog, InitialPrompt = "Well <b>hello</b> there."
```

## Quick example

```
I <shake>can't</shake> believe<pause=0.5> it. The <color=#ff4040>bridge</color> is <b>gone</b>.
```

- "can't" shakes.
- Typing stops for half a second after "believe".
- "bridge" is red.
- "gone" is bold.

The tags themselves never show on screen.

## Span tags

Span tags style everything between `<tag>` and `</tag>`.

| Tag | Argument | Effect |
|---|---|---|
| `<b>` | none | Bold. Bold letters are wider, and line wrapping accounts for that. |
| `<i>` | none | Italic. Italic letters can be a different width, and line wrapping accounts for that. |
| `<color=#ff4040>` | Hex color, with or without `#`, 6 or 3 digits (`#f00`) | Text color |
| `<color=default>` | The word `default` | The character's own text color, even inside another `<color>` |
| `<shake>` `<shake=2>` | Optional intensity, any number (default 1) | Each letter shakes on its own |
| `<wave>` `<wave=2>` | Optional intensity, any number (default 1) | Letters bob in a wave |
| `<speed=2>` | Number above 0 | Types this part 2x as fast; `0.5` is half speed |

Close a span with its name: `</b>`, `</i>`, `</color>`, `</shake>`, `</wave>`, `</speed>`. Closing tags never take an argument.

Text with no color tag is drawn in the character's default color (the `TextColor3` of the `_LETTER_REF` in its `DialogueUI`). `<color=default>` gets back to it from inside a colored span, and `</color>` goes back to whatever color was open before:

```
<color=#ff4040>danger, <color=default>calm again</color>, red again</color>
```

## Instant tags

Instant tags happen at one point in the line and have no closing tag. Each one fires right before the next character is typed. An instant tag at the very end of a line fires after the last character.

| Tag | Argument | Effect |
|---|---|---|
| `<pause=0.5>` | Seconds, 0 or more | Waits before typing on |
| `<sfx=Name>` | Sound name, not empty, spaces allowed | Plays that sound |
| `<event=Name>` | Event name, not empty, spaces allowed | Fires a named dialogue event for scripts to react to, mid line |
| `<anim=Name>` | Animation name, not empty, spaces allowed | Plays that animation on the character |
| `<stopanim=Name>` | Animation name, not empty, spaces allowed | Stops that animation on the character |

Several instant tags in a row all fire at the same point, in the order written: `Wait.<pause=1><sfx=Gasp> What?`

## Tag syntax rules

- **Names are letters only and are not case sensitive.** `<B>`, `<Color=#fff>` and `</COLOR>` all work.
- **No spaces around `=`.** `<color=#ff0000>` works; `<color = #ff0000>` is not a tag and shows as plain text.
- **An argument can hold anything except `<` and `>`.** That includes spaces: `<sfx=Door Slam>`.
- **Tags take an argument only where the tables above give one.** `<b=1>` is not a tag.

## Combining tags

**Nesting.** Tags stack freely: `<b><color=#ff0000>LOUD</color></b>` is bold and red.

**The same kind twice.** The most recently opened tag wins. Closing it brings the outer one back:

```
<color=#ff0000>red <color=#0000ff>blue</color> red again</color>
```

**Closing out of order is fine.** A closing tag closes the most recent open tag with that name, whatever was opened after it:

```
<b><shake>bold and shaking</b> only shaking</shake> plain
```

**Unclosed tags run to the end of the line.** `<b>everything from here is bold` needs no `</b>`.

**Effects stack across kinds.** `<shake><wave>...</wave></shake>` gives letters that both shake and wave.

## Escapes and special characters

| Write | To get |
|---|---|
| `\<` | A literal `<` that is never read as a tag |
| `\\` | A literal `\` |

Any other backslash is kept as is. In particular, `\n` typed as two characters is **not** a line break. A line only breaks on a real newline character, or where it wraps because it is too long. A Studio property box can't take a real newline, so breaks typed into `InitialPrompt` don't work yet. Use wrapping, or set the text from a script.

Accented letters and emoji (including skin tones and other combined emoji) each count as a single character, so they type, wrap and animate as one letter.

## Broken tags

The parser never drops text it can't use. A tag that is invalid for any reason shows on screen exactly as written, so typos are visible instead of silently vanishing. Reasons a tag is invalid:

- Unknown name: `<unknown>`
- Bad argument: `<color=notacolor>`, `<speed=0>`, `<pause=-1>`, `<sfx=>`, `<event=>`, `<anim=>`
- An argument where none belongs: `<b=1>`
- A closing tag with nothing open by that name: a stray `</b>`
- Spaces inside the tag: `<color = #fff>`

To show a tag on purpose, escape it: `\<b>` shows `<b>`.

## How a line gets on screen

The framework runs entirely on the server. Players never run its code. A line goes through three steps, all in `API/v1/Modules/Dialogue`:

1. **Markup** (`Markup.parse`) turns the tagged text into a list of characters, each with its style, plus the instant-tag events keyed to the character they fire before.
2. **Layout** (`Layout.build`) wraps the characters into lines and measures where each visible letter sits. Lines break at spaces, after hyphens and at newlines. A word too long for a whole line breaks between its letters. Bold and italic are the only styles that change a letter's width.
3. **Board** clones one `TextLabel` per letter into the character's `DialogueUI` BillboardGui at its measured spot, using the letter's color, boldness and slant.

```luau
local board = Dialogue.Board.new(character.Head.DialogueUI)
board.ShowAll(board.Build("Well <b>hello</b> there."))
```

## What works today

| Feature | Parsed | Shown on screen |
|---|---|---|
| `<b>`, `<i>` | Yes | Yes |
| `<color>` (including `default`) | Yes | Yes |
| Wrapping and alignment | Yes | Yes (centered by default) |
| `<shake>`, `<wave>` | Yes | Not yet |
| `<speed>`, `<pause>` | Yes | Not yet |
| `<sfx>` | Yes | Not yet |
| `<event>` | Yes | Not yet (the scripting callback doesn't exist yet) |
| `<anim>`, `<stopanim>` | Yes | Not yet |

Today a whole line appears at once. Typing letters out one by one, and the effects, speed, pauses and sounds that depend on it, will come with the Presenter, which isn't built yet. Lines with those tags can still be written now; the tags are parsed and kept, so they'll start working when the Presenter does.
