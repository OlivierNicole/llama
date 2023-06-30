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
