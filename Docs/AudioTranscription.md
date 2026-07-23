# Key Whisper transcription parameters (most impact on accuracy/speed) are:

1. --model — model size (tiny→large); larger = better accuracy, slower/more VRAM. Configurable.
2. --language — set known language explicitly for better results. Configurable, defaults to `en`.
3. --task — transcribe (same language) vs translate (to English). Configurable, defaults to `transcribe`.
4. --beam_size — higher can improve accuracy (common: 5), slower decode. Configurable, defaults to `5`.
5. --temperature — lower is more deterministic (0 to 0.2 typical for clean speech). Configurable, defaults to `0`.
6. --best_of — number of candidates (used with sampling); better quality, slower. Configurable (optional), defaults to `nil` - beam size is more important.
7. --condition_on_previous_text — keeps context across segments; can help consistency. Configurable, defaults to `true`.
8. --initial_prompt — domain vocabulary/context primer (names, jargon). Configurable, defaults to `nil`
9. --word_timestamps — enables word-level timing (useful for subtitles/alignment). Required (not configurable), set to `true`,
10. --fp16 / device settings — speed/memory tradeoff (fp16 on GPU; disable on CPU). Required (not configurable).

A strong default starting point is: model=medium or large-v3, language set, task=transcribe, beam_size=5, temperature=0, word_timestamps=true.

## Supported languages

For OpenAI Whisper CLI, --language accepts either the language name (e.g. english) or these language codes:

af, am, ar, as, az, ba, be, bg, bn, bo, br, bs, ca, cs, cy, da, de, el, en, es, et, eu, fa, fi, fo, fr, gl, gu, ha, haw, he, hi, hr, ht, hu, hy, id, is, it, ja, jw, ka, kk, km, kn, ko, la, lb, ln, lo, lt, lv, mg, mi, mk, ml, mn, mr, ms, mt, my, ne, nl, nn, no, oc, pa, pl, ps, pt, ro, ru, sa, sd, si, sk, sl, sn, so, sq, sr, su, sv, sw, ta, te, tg, th, tk, tl, tr, tt, uk, ur, uz, vi, yi, yo, yue, zh

If --language is omitted, Whisper auto-detects language.

## Suport model names

Common Whisper model names are:

* tiny
* base
* small
* medium
* large

Depending on your Whisper install/version, you may also have:

* large-v2
* large-v3
* large-v3-turbo
* turbo

## Progress feedback

`AudioTranscriber.transcribeAudio(...)` can report normalized progress and ETA across all
segments via a closure callback. For async code, `transcribeAudioProgressStream(...)` exposes
the same updates as an `AsyncThrowingStream`.

```swift
let transcription = try transcriber.transcribeAudio(
    from: segments,
    audioSegmentSourceURL: sourceURL
) { progress in
    print(progress.fractionCompleted)
    print(progress.estimatedTimeRemaining ?? .seconds(0))
}
```

```swift
for try await event in transcriber.transcribeAudioProgressStream(
    from: segments,
    audioSegmentSourceURL: sourceURL
) {
    switch event {
    case let .progress(update):
        print(update.message ?? "Transcribing...")
    case .completed(let result):
        print(result.plainLines)
    }
}
```