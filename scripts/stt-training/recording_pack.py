#!/usr/bin/env python3
"""Create a synthetic readout plan; it contains no training audio or labels."""
import argparse
import csv
import json
import random
from pathlib import Path


def prompts():
    rows = []

    def add(category, text, **expected):
        rows.append({'prompt_id': f'FIELD-{len(rows) + 1:03}', 'category': category,
                     'read_aloud': text, 'synthetic_script': True, 'expected': expected})

    for spoken, value in [
        ('eight point two', -8.2), ('eighteen point two', -18.2),
        ('eighteen point one nine', -18.19), ('eighteen point zero nine', -18.09),
        ('eighteen point nine zero', -18.90), ('twenty eight point two', -28.2),
        ('seventeen point eight', -17.8), ('nineteen point one', -19.1),
        ('zero point five', -.5), ('zero point zero five', -.05),
        ('thirty point zero five', -30.05), ('twenty seven point two five', -27.25),
    ]:
        add('optical_rx', f'The optical receive reading was minus {spoken} d B M.', optical_rx_dbm=value)
        add('optical_paraphrase', f'I measured received optical power at negative {spoken} decibel milliwatts.', optical_rx_dbm=value)
    for text, value, unit in [
        ('The splice loss was zero point zero two d B.', .02, 'dB'),
        ('The splice loss was zero point two d B.', .2, 'dB'),
        ('The total insertion loss was two point zero d B.', 2, 'dB'),
        ('The O T D R event was thirteen point five metres from the chamber.', 13.5, 'm'),
        ('The fibre length was one hundred and fifty metres.', 150, 'm'),
        ('The O T D R distance was one point two five kilometres.', 1.25, 'km'),
        ('The broadband sync speed was fifty two point four megabits per second.', 52.4, 'Mbps'),
        ('The final sync was forty one point seven megabits per second.', 41.7, 'Mbps'),
        ('The initial sync was seven point two megabits per second.', 7.2, 'Mbps'),
        ('The power supply output was twelve volts.', 12, 'V'),
        ('The meter showed zero volts.', 0, 'V'),
        ('The socket measured two hundred and thirty volts.', 230, 'V'),
        ('The download test measured nine hundred megabits per second.', 900, 'Mbps'),
        ('The upload test measured one hundred and ten megabits per second.', 110, 'Mbps'),
    ]:
        add('other_measurement', text, measurement=value, unit=unit)
    for text, value in [
        ('The reading is eighteen point two, no no sorry the reading is minus eighteen point one nine.', -18.19),
        ('Optical receive was minus eighteen point two d B M, sorry minus eighteen point one nine d B M.', -18.19),
        ('The optical receive was minus nineteen point one d B M. Correction, the optical receive was minus eighteen point zero nine d B M.', -18.09),
        ('The optical reading was minus eighteen point two d B, sorry the optical reading was minus eighteen point two d B M.', -18.2),
        ('The reading was minus, sorry, negative zero point zero five d B M.', -.05),
        ('Optical receive was minus twenty eight point two d B M. The transmit power was plus two point one d B M.', -28.2),
    ]:
        add('correction_or_contrast', text, optical_rx_dbm=value)
    for text in [
        'I have not measured optical receive power yet.',
        'The service test did not pass. A return visit is required.',
        'I have not completed the job. The site is safe and civils are required.',
        'The expected reading is minus eighteen point two d B M; I have not measured the actual receive power.',
        'The optical receive reading might be minus eighteen point two d B M. I need to check the meter.',
        'The splice loss is zero point two d B. That is not the receive power.',
        'The reading could be minus eighteen point two or minus nineteen point one d B M. I am not sure.',
        'The customer did not authorise internal wiring work.',
    ]:
        add('negative_uncertain_or_missing', text, require_clarification=True)
    for text in [
        'I checked the O N T, C B T and C S P. The P O N light is green and L O S is off.',
        'The serving asset is C B T dash S Y N dash one zero.',
        'The O N T serial is O N T dash S Y N dash one eight.',
        'I used the existing duct for the fibre route and checked the external splice.',
        'The F T T P service test passed. The customer is online.',
        'I re-spliced at the C S P and checked the O T D R trace.',
        'The duct is blocked thirteen point five metres from the chamber. Civils are required.',
        'The pole inspection was not satisfactory. Work has stopped pending a safety review.',
        "Hello I'm Waseem from local, sorry I stay here, sorry I'm Waseem from Bangalore.",
        'Yes, the serving asset is C B T dash S Y N dash one zero. No further work is required.',
        'No, sorry, one more detail. The optical received measurement was minus eighteen point one nine d B M.',
        'The equipment was installed in the hall, sorry the equipment was installed in the living room.',
    ]:
        add('terms_and_spontaneous_restarts', text)
    opening = 'I installed the ONT in the living room. I used the existing duct for the fibre route. '
    for reading in ['minus eighteen point two', 'minus eighteen point one nine', 'minus zero point five']:
        add('s1_summary', opening + f'The optical receive reading was {reading} d B M. '
            'The service test passed. The job is fully completed. I showed the customer the equipment.')
    for text in [
        'The asset is C B T dash S Y N dash one zero. No further work is required.',
        'Sorry, the optical receive reading was minus eighteen point one nine d B M. A return visit is required.',
        'No. Actually, the customer needs a return visit tomorrow. The receiving team is provisioning.',
        'That is everything, thank you.',
        'The service test failed, sorry the service test passed. The customer is now online.',
    ]:
        add('anything_else_response', text)
    return rows


def create(output):
    output.mkdir(parents=True, exist_ok=False)
    rows = prompts()
    (output / 'prompts.json').write_text(json.dumps(rows, indent=2) + '\n')
    with (output / 'prompts.csv').open('w') as f:
        writer = csv.DictWriter(f, fieldnames=['prompt_id', 'category', 'read_aloud'])
        writer.writeheader()
        writer.writerows({k: r[k] for k in writer.fieldnames} for r in rows)
    speakers = []
    sheets = output / 'speaker-sheets'; sheets.mkdir()
    for accent, prefix in [('en-IN', 'IN'), ('en-GB', 'GB')]:
        for i in range(1, 9):
            speaker = f'{prefix}{i:02}'
            split = 'train' if i <= 6 else 'dev' if i == 7 else 'test'
            speakers.append({'speaker_id': speaker, 'accent': accent, 'split': split})
            order = rows[:]; random.Random(speaker).shuffle(order)
            with (sheets / f'{speaker}.csv').open('w') as f:
                writer = csv.writer(f)
                writer.writerow(['prompt_id', 'read_aloud', 'audio_filename', 'verified_transcript'])
                for r in order:
                    writer.writerow([r['prompt_id'], r['read_aloud'], f'{speaker}-{r["prompt_id"]}.wav', ''])
    (output / 'speakers.json').write_text(json.dumps(speakers, indent=2) + '\n')
    example = {'id': 'IN01-FIELD-001', 'speaker_id': 'IN01', 'accent': 'en-IN', 'session_id': 'IN01-session1',
               'audio': 'audio/IN01-FIELD-001.wav', 'text': '', 'human_verified': False,
               'training_allowed': False, 'synthetic': False}
    (output / 'recordings.example.jsonl').write_text(json.dumps(example) + '\n')
    print(json.dumps({'output': str(output), 'prompts': len(rows), 'plannedSpeakers': len(speakers), 'audioIncluded': False}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    create(parser.parse_args().output)
