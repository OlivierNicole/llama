open Llama_interactive
open Dsl

let mk_voice gate freq_hz effect_clock =
  let sah_noise = sample_and_hold (noise_01 ()) effect_clock in
  let lfo = low_frequency_oscillator (const Sine) (const 0.2) (trigger gate) in
  let freq_signal = const freq_hz in
  let osc =
    mean
      [
        oscillator (const Saw) freq_signal;
        oscillator (const Saw) (freq_signal |> scale 2.0);
      ]
  in
  let release_s = const 0.1 in
  let filter_env =
    adsr_linear ~gate ~attack_s:(const 0.2) ~decay_s:(const 0.1)
      ~sustain_01:(const 1.0) ~release_s
  in
  let filtered_osc =
    chebyshev_low_pass_filter osc ~epsilon:(const 5.0)
      ~cutoff_hz:
        (sum
           [
             const 100.0;
             filter_env |> scale 1000.0;
             sah_noise |> scale 500.0;
             lfo |> scale 500.0;
           ])
  in
  let amp_env =
    asr_linear ~gate ~attack_s:(const 0.01) ~release_s |> exp_01 1.0
  in
  lazy_amplifier filtered_osc ~volume:amp_env
  |> map ~f:(fun x -> Float.clamp_sym ~mag:2.0 (x *. 10.0))

let mk_voices_row ~key_gates_in_order ~note_for_second_key ~effect_clock =
  let base_index = Music.Note.to_midi_index note_for_second_key - 1 in
  sum
    (List.mapi key_gates_in_order ~f:(fun i gate ->
         let midi_index = base_index + i in
         let freq_hz = Music.frequency_hz_of_midi_index midi_index in
         mk_voice gate freq_hz effect_clock))

let mk_voices (keys : bool Signal.t Input.All_keyboard.t) =
  let effect_clock = clock (const 8.0) in
  let top_row =
    [
      keys.key_q;
      keys.key_w;
      keys.key_3;
      keys.key_e;
      keys.key_4;
      keys.key_r;
      keys.key_t;
      keys.key_6;
      keys.key_y;
      keys.key_7;
      keys.key_u;
      keys.key_8;
      keys.key_i;
      keys.key_o;
      keys.key_0;
      keys.key_p;
    ]
  in
  let bottom_row =
    [
      keys.key_z;
      keys.key_x;
      keys.key_d;
      keys.key_c;
      keys.key_f;
      keys.key_v;
      keys.key_b;
      keys.key_h;
      keys.key_n;
      keys.key_j;
      keys.key_m;
      keys.key_k;
      keys.key_comma;
      keys.key_period;
      keys.key_semicolon;
    ]
  in
  sum
    [
      mk_voices_row ~key_gates_in_order:top_row ~note_for_second_key:(`C, 4)
        ~effect_clock;
      mk_voices_row ~key_gates_in_order:bottom_row ~note_for_second_key:(`C, 3)
        ~effect_clock
      |> scale 0.5;
    ]

(* Removes any sharp changes from the mouse position which could cause bad
   sounds to come out of the filter controlled by the mouse *)
let mouse_filter =
  butterworth_low_pass_filter ~half_power_frequency_hz:(const 10.0)

let mk_synth (input : (bool Signal.t, float Signal.t) Input.t) =
  let mouse_x = mouse_filter input.mouse.mouse_x in
  let mouse_y = mouse_filter input.mouse.mouse_y in
  let echo_effect signal = signal |> scale 0.6 in
  mk_voices input.keyboard
  |> chebyshev_low_pass_filter
       ~epsilon:(mouse_y |> exp_01 1.0 |> scale 10.0)
       ~cutoff_hz:(mouse_x |> exp_01 4.0 |> scale 8000.0 |> offset 100.0)
  |> echo ~f:echo_effect ~delay_s:(const 0.3)
  |> echo ~f:echo_effect ~delay_s:(const 0.5)

let () =
  with_window (fun window ->
      let signal = mk_synth (Window.input_signals window) in
      let viz'd_signal =
        visualize ~stable:true ~stride:4 ~sample_scale:0.05
          ~sample_to_rgba_01:(fun x ->
            let g = 0.0 in
            let rb = 0.2 +. Float.abs x in
            (rb, g, rb, 1.0))
          window signal
      in
      play_signal ~scale_output_volume:0.1 viz'd_signal)
