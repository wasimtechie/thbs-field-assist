# Field engineering speech adaptation: recording and training pack

Status: **prepared, not trained**. There are no real engineer recordings yet.
The app still uses the published Moonshine Small Streaming model. Fine-tuning
cannot promise to recognize every measurement or every Indian/UK English accent.
We will measure the result before replacing the working offline model.

## What to record

The generated pack contains **72 synthetic scripts**, 16 suggested anonymous
speaker IDs and randomized readout sheets. Six speakers from each accent group
are allocated to training, one to development and one to the final test set.
These are initial allocations, not evidence of adequate accent coverage.
Include several Indian English regional backgrounds and several UK English
regional backgrounds; speak naturally rather than imitating an accent. Add more
held-out speakers as the collection grows.

Aim initially for roughly **2–5 hours of verified real audio** spread across
speakers, phones, quiet/outdoor settings and realistic background noise. This is
a pilot collection target, not a proven minimum for this model/use case. Keep
about 20% of the collection as spontaneous, unscripted job summaries and
corrections, particularly in the held-out sets. Do not use the test speakers or
test sessions to tune prompts, adapters, vocabulary boosts or endpoint settings.

The scripts cover signed/decimal optical receive readings, transmit versus
receive power, splice/insertion loss, OTDR distance, fibre length, broadband
sync/throughput, voltage, asset identifiers, engineering acronyms, uncertain or
unmeasured values, corrections and “anything else” responses. The broader
measurement scripts train recognition; they do not add those fields to the
current six-field FTTP demo or establish official operational requirements.

Generate a fresh pack from the repository root:

```sh
python3 scripts/stt-training/recording_pack.py --output .local/my-recording-pack
```

Open `prompts.csv`, `speakers.json` and the relevant `speaker-sheets/*.csv`.
Scripts are synthetic examples. Keep actual customer details out of these
training readouts. Use recordings you are authorised to use for training.

Record each clip as **16 kHz mono PCM16 WAV**, 1–35 seconds, with a little quiet
before and after speech. Longer reports should be split at natural pauses.
Keep a quiet and a realistic-noise subset; do not add noise to a clipped or
unintelligible recording and call it labelled data. Listen back and transcribe
what was actually said. If a speaker deviates from the readout, change the
transcript rather than assuming they read the prompt correctly.

**ASR labels must retain self-corrections.** For example:

```text
The reading is 18.2, no no sorry the reading is minus 18.19.
```

Do not train ASR with the shortened label “minus 18.19” for that audio. That
would teach it to omit spoken evidence. The app's interpretation layer resolves
the final form value separately and retains the original speech transcript.
Cased, punctuated transcripts with consistent numeric/unit formatting are
appropriate; preserve the words, sign, digits and correction rather than
rewriting the engineer's meaning.

## Build a verified dataset

Create `recordings.jsonl` using `recordings.example.jsonl` as the schema:

```json
{"id":"IN01-FIELD-001","speaker_id":"IN01","accent":"en-IN","session_id":"IN01-session1","audio":"audio/IN01-FIELD-001.wav","text":"The optical receive reading was minus 8.2 dBm.","human_verified":true,"training_allowed":true,"synthetic":false}
```

Use `en-GB` for the UK group. Speaker IDs are anonymous labels, not customer
or engineer names. Only mark transcripts verified after listening to the clip.

```sh
python3 scripts/stt-training/dataset.py \
  --manifest .local/my-recording-pack/recordings.jsonl \
  --speakers .local/my-recording-pack/speakers.json \
  --output .local/field-speech-dataset
```

The validator rejects missing/unchecked labels, unknown speakers, accent
mismatches, overlapping recording sessions, duplicate audio, missing accent
groups, invalid WAV formats, near-silence and heavy clipping. It copies validated
audio into a portable dataset and hashes the audio and manifests. It never
overwrites an existing output folder.

Whole speakers and sessions are held out. Dedicated development speakers are
placed at the end of `train-dev.jsonl`; their exact duration configures the
upstream trainer's tail-based development slice. `test.jsonl` is scored after
training and does not participate in optimizer steps or early stopping. Keep
the test set for the decision, rather than repeatedly adapting to its failures.

## Training setup

The official trainer supports LoRA on the streaming model. Its published worked
examples mainly use Medium; this setup explicitly selects **Small**, matching
our product choice, and still requires an actual GPU trial. The inspected CLI
and source are pinned in
[`sources.lock.json`](../../fixtures/voice/training/sources.lock.json).

Use a separate Linux/CUDA environment with Python 3.11+; install a compatible
CUDA PyTorch build for that machine, then the training requirements. A T4-class
GPU is a reasonable initial trial, but Small's actual training memory and time
must be measured. This Mac has no CUDA GPU. No remote machine/job has been
created or charged, and no recordings are uploaded by these preparation tools.

```sh
python3 -m venv .venv-train
. .venv-train/bin/activate
python -m pip install -r scripts/stt-training/requirements-training.txt
python scripts/stt-training/train.py --stage-base
python scripts/stt-training/train.py --dataset .local/field-speech-dataset
```

The last command **only prints a plan**. The model download is pinned to
`moonshine-ai/moonshine-streaming-small` revision
`2c036506f23a09c18df5a50057599ba6d9280999`; it does not silently select the
trainer's default Medium checkpoint. Preparation needs internet access for
dependencies, the public checkpoint and later replay/canary corpora. Mobile
inference remains local after qualified weights are bundled.

To run the printed plan on the prepared GPU machine:

```sh
python scripts/stt-training/train.py \
  --dataset .local/field-speech-dataset \
  --output .local/moonshine-training/field-small-run-01 \
  --execute
```

The initial configuration uses rank-8 LoRA on encoder and decoder attention,
learning rate `1e-4`, batch size 4, early stopping and 50% general speech replay.
The encoder is included because accents and acoustic conditions are part of the
request. Compare against a decoder-only run (`1e-3`) once a baseline is measured;
these are starting configurations, not selected optimal hyperparameters.
General speech replay and the LibriSpeech canary help expose general accuracy
regression. The tools refuse modified data, a different training package/base
identity, missing CUDA or overwriting an existing candidate run.

## Evaluate, export and qualify

Evaluate the published baseline and trained candidate on the **same held-out
clips**. Report results separately for Indian English and UK English, quiet and
noisy speech, complete summaries and short answers. WER alone is insufficient:
check exact sign, decimal digits, unit, receive/transmit distinction, spelled
asset IDs, negations and preservation of correction words. Also run the app's
form extraction and complete “anything else” journey against those transcripts.
A missing minus sign must never be repaired from an expected operating range.

No numerical improvement threshold is claimed before the baseline is measured.
Require improvement in critical-field errors in both accent groups, no material
regression in general speech, and acceptable real-phone latency/memory before
selection. Synthetic audio is useful for regression tests and cannot establish
real accent performance.

Once a candidate passes, use the official export/quantization path. Because
this configuration adapts the encoder too, export **all graphs**:

```sh
python -m moonshine_voice.lora --export \
  --model .local/moonshine-training/field-small-run-01/adapted \
  --output-dir .local/moonshine-training/exported-float \
  --graphs all \
  --tokenizer-bin .local/model-assets/moonshine-small-streaming/tokenizer.bin
bash /path/to/pinned-moonshine/scripts/quantize-streaming-model.sh \
  .local/moonshine-training/exported-float
```

Check tokenizer compatibility, export parity, signed measurements, streaming
endpoint behavior, both mobile runtimes and model-package integrity before
replacing the pinned app assets. Re-measure package size, working memory and
end-to-end response time. Merging LoRA avoids a separate adapter runtime in the
phone, but export/quantization and performance still need validation. The
current app assets and APK remain untouched by the training tools.

Primary references: [Moonshine customization and training](https://moonshine-voice.readthedocs.io/en/stable/models/domain-customization/),
[pinned trainer CLI](https://github.com/moonshine-ai/moonshine/blob/234f60faa0eb388b01cdf7e60aca232af37aefda/language-bindings/python/src/moonshine_voice/lora/__main__.py),
[official Small checkpoint](https://huggingface.co/moonshine-ai/moonshine-streaming-small).
