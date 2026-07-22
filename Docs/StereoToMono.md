# Key FFmpeg parameters for stereo → mono are:

1. -ac 1 — sets output to 1 channel (mono).
2. -af "pan=mono|c0=0.5*c0+0.5*c1" — explicit downmix (equal L/R blend, safest).
3. -c:a \<codec\> — choose output codec (e.g., pcm_s16le, aac, libmp3lame).
4. -ar \<rate\> — sample rate (e.g., 44100 or 48000) if you need to resample.
5. -b:a \<bitrate\> — bitrate for lossy formats (e.g., 128k for MP3/AAC).

## Reliable example:

`ffmpeg -i input.wav -af "pan=mono|c0=0.5*c0+0.5*c1" -ac 1 output.wav`

For voice-focused mono, you can weight channels differently (e.g., 0.7*c0+0.3*c1) if one side is cleaner.