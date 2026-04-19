# 🎹 DE2 Electronic Organ (Verilog FPGA Project)

A fully hardware-based electronic organ implemented on the **Altera DE2 (Cyclone II EP2C35F672C6)** FPGA using **Verilog HDL**.  
The system generates real-time audio with multiple instruments, effects, and rhythm control — without any software processor.

---

## 📌 Features

- 12 chromatic notes (C–B)
- Polyphonic playback (chords)
- 4 instruments:
  - Organ (sine)
  - Harp (sawtooth)
  - Flute (triangle)
  - Pipe organ (harmonic synthesis)
- Audio effects:
  - Reverb
  - Distortion
- Metronome (120 BPM)
- Sustain functionality
- Stereo audio output via **WM8731 codec (I2S)**
- Hardware-only design (no CPU)

---

## 🧠 System Architecture

SW[0–11] → 12× DDS Oscillators → Chord Mixer → Effects (Distortion → Reverb)  
→ (optional mix with Metronome)  
→ I2S Transmitter → WM8731 Codec → Audio Output

---

## 🧩 Modules Overview

### 1. `top_level.v`
- Main module
- Instantiates and connects all components
- Handles control logic:
  - sustain
  - octave selection
  - rhythm toggle
- Maps FPGA I/O

### 2. `dds_oscillator.v`
- Direct Digital Synthesis oscillator
- 32-bit phase accumulator
- Generates waveform samples
- 12 parallel instances (one per note)

### 3. `note_freq_table.v`
- Converts note + octave → frequency word
- Uses DDS formula:
freq_word = frequency × 2³² / sample_rate

### 4. `waveform_rom.v`
- Lookup table for waveforms
- 4 wave types:
  - sine
  - sawtooth
  - triangle
  - harmonic mix

### 5. `chord_mixer.v`
- Sums all active oscillators
- Prevents overflow using scaling
- Outputs 16-bit audio

### 6. `effects.v`
- Chains audio effects:
  1. Distortion (clipping)
  2. Reverb

### 7. `reverb.v`
- Circular buffer delay line
- ~84 ms delay
- 50% feedback
- 50/50 dry/wet mix

### 8. `rhythm_gen.v`
- Generates metronome (120 BPM)
- Produces short click pulses
- Drives LED beat indicator

### 9. `i2s_transmitter.v`
- Sends audio to WM8731 codec
- Generates clocks:
  - MCLK (12.5 MHz)
  - BCLK (3.125 MHz)
  - LRCK (~48.8 kHz)
- Stereo output (L = R)

### 10. `wm8731_i2c_ctrl.v`
- Configures WM8731 codec via I2C
- Sends initialization sequence
- Enables DAC output

---

## 🎛 Controls (DE2 Board)

### Switches
| Switch | Function |
|--------|--------|
| SW[11:0] | Notes (C–B) |
| SW[13:12] | Instrument select |
| SW[14] | Reverb ON/OFF |
| SW[15] | Distortion ON/OFF |
| SW[16] | Lower octave |
| SW[17] | Higher octave |

### Buttons
| Button | Function |
|--------|--------|
| KEY[0] | Reset |
| KEY[1] | Toggle metronome |
| KEY[2] | Sustain |
| KEY[3] | Unused |

---

## 🔊 Audio System

- Sample rate: ~48.8 kHz
- Resolution: 16-bit
- Output: Stereo (duplicated mono)
- Codec: **WM8731**
- Protocols:
  - I2S (audio)
  - I2C (configuration)

---

## ⚙️ Quartus Setup

1. Create a new project  
2. Add all `.v` files  
3. Set top-level entity: `top_level`  
4. Select device: `Cyclone II → EP2C35F672C6`  
5. Compile the project  

---

## ⚠️ Requirements

- Quartus II 13.0 SP1  
- Cyclone II device support installed  
- DE2 board with WM8731 codec  

---

## 📊 Key Concepts

- Direct Digital Synthesis (DDS)  
- Fixed-point arithmetic  
- FPGA-based audio processing  
- Hardware timing (no PLL)  
- Digital signal effects  

---

## 🚀 Possible Improvements

- Add ADSR envelope generator  
- Implement filters (low-pass / high-pass)  
- Add MIDI input support  
- Use external RAM for longer reverb  
- Improve volume normalization  

---

## 📄 License

Educational / academic use.
