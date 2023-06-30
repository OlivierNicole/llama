# Language for Live Audio Module Arrangement

*The llama is a domesticated South American camelid.*

## About

`llama` is a library for building software-defined modular synthesizers in a
declarative style. It can be used to implement programs that generate audio
using components that should be familiar to anyone who has played with a
synthesizer before. It can also be used from `utop` or other ocaml repl
environments to perform music live.

## Getting Started

You will need to [install rust](https://rustup.rs/) to build the low level
library that reads wav files and talks to the sound card. These parts are
written in rust because rust has really good libraries for wav decoding
([hound](https://crates.io/crates/hound)) and sound card interaction
([cpal](https://crates.io/crates/cpal)).

Then you should be able to build and run an example program with:
```
dune exec ./examples/polyphonic_events.exe
```

## Concepts

The `'a Signal.t` type represents a buffered stream of values of type `'a` and
is central to the API of `llama`. These are used to send audio and control
signals through a network of components. For example:

```ocaml
open Llama
open Dsl

(* [osc] represents a signal whose value varies between -1 and 1 according
   to a 440Hz sine wave. *)
let osc : float Signal.t = oscillator (const Sine) (const 440.0)

(* [note_clock] represents a signal whose value is either [true] or [false]
   which changes from [false] to [true] twice per second, and spends 30% of the
   time on. This is often used to communicate the fact that a key is pressed to
   a module that responds to such events. *)
let note_clock : bool Signal.t =
  pulse ~frequency_hz:(const 2.0) ~duty_01:(const 0.5)

(* [envelope] is a signal which is 0 while its [gate] argument is producing
   [false] values, but which raises to 1 over the course of [attack_s] seconds
   when [gate] transitions to [true], and transitions back to [false] when
   [gate] transitions to [false]. Note that even though it is also a [float
   Signal.t] like [osc] is, it doesn't contain audio data. Instead an envelope
   is typically used to modulate a signal in response to a key press, which we
   are simulating here with [note_clock]. *)
let envelope : float Signal.t =
  asr_linear ~gate:note_clock ~attack_s:(const 0.01) ~release_s:(const 0.2)

(* Finally, multiply the oscillator with the envelope to produce a repeating
   burst of volume which slowly tapers off twice per second *)
let output : float Signal.t = osc *.. envelope
let () = play_signal output
```

## Example Session

Start a utop session with the `Llama` module available by running `$ dune
utop`, then enter this into the utop repl.

```ocaml
open Llama.Live;;

(* Define a sequence of frequencies and durations. *)
let steps = [ Some (110.0, 0.1); Some (123.47, 0.1); Some (98.0, 0.2); None ]
|> List.map (Option.map (fun (freq, period) -> { value = const freq; period_s = const period }));;

(* Create a sequencer to play the notes. *)
let { value = freq; gate } = step_sequencer steps (clock (const 4.0));;

(* Create an oscillator to buzz at the frequency selected by the sequencer. *)
let osc = oscillator (const Saw) freq;;

(* Create an envelope generator to shape the volume according to the gate. *)
let env = asr_linear ~gate ~attack_s:(const 0.01) ~release_s:(const 0.2);;

(* Use the envelope to control the volume of the oscillator. *)
let amp = osc *.. env

(* Create a player returning a `float t ref` which can be set to the signal we want to play. *)
let out = go ();;

(* Play! *)
out := amp;;

(* To silence playback you can change the output to [silence]. *)
out := silence;;
```
