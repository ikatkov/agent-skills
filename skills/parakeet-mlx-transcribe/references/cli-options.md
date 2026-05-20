# Parakeet MLX CLI Options

This reference describes the `parakeet-mlx` root command interface.

## Command

```bash
parakeet-mlx [OPTIONS] AUDIOS...
```

## Inputs

- Positional `audios`: one or more readable files.

## Core Options

- `--model TEXT` (default `mlx-community/parakeet-tdt-0.6b-v3`)
- `--output-dir PATH` (default `.`)
- `--output-format [txt|srt|vtt|json|all]` (default `srt`)
- `--output-template TEXT` (default `{filename}`)
- `--highlight-words / --no-highlight-words` (default `false`)

## Decoding and Chunking

- `--decoding [greedy|beam]` (default `greedy`)
- `--chunk-duration FLOAT` (seconds, default `120`, `0` disables chunking)
- `--overlap-duration FLOAT` (seconds, default `15`)
- `--beam-size INTEGER` (default `5`)
- `--length-penalty FLOAT` (default `0.013`)
- `--patience FLOAT` (default `3.5`)
- `--duration-reward FLOAT` (default `0.67`)

## Sentence Segmentation

- `--max-words INTEGER`
- `--silence-gap FLOAT`
- `--max-duration FLOAT`

## Runtime/Performance

- `--verbose, -v`
- `--fp32 / --bf16` (default `--bf16`)
- `--local-attention / --full-attention` (default `--full-attention`)
- `--local-attention-context-size INTEGER` (default `256`)
- `--cache-dir PATH`

## Shell Completion and Help

- `--install-completion`
- `--show-completion`
- `--help`

## Environment Variables

- `PARAKEET_MODEL`
- `PARAKEET_OUTPUT_FORMAT`
- `PARAKEET_OUTPUT_TEMPLATE`
- `PARAKEET_DECODING`
- `PARAKEET_CHUNK_DURATION`
- `PARAKEET_OVERLAP_DURATION`
- `PARAKEET_BEAM_SIZE`
- `PARAKEET_LENGTH_PENALTY`
- `PARAKEET_PATIENCE`
- `PARAKEET_DURATION_REWARD`
- `PARAKEET_MAX_WORDS`
- `PARAKEET_SILENCE_GAP`
- `PARAKEET_MAX_DURATION`
- `PARAKEET_FP32`
- `PARAKEET_LOCAL_ATTENTION`
- `PARAKEET_LOCAL_ATTENTION_CTX`
- `PARAKEET_CACHE_DIR`
