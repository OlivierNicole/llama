exception Parse_exception = Byte_array_parser.Parse_exception

let sprintf = Printf.sprintf

module Unknown = struct
  type t = Unknown of string
end

open Unknown

module Chunk_type = struct
  type t = Header | Track

  let of_string_opt = function
    | "MThd" -> Some Header
    | "MTrk" -> Some Track
    | _ -> None

  let parse_result : (t, Unknown.t) result Byte_array_parser.t =
    let open Byte_array_parser in
    let+ name = string4 in
    match of_string_opt name with
    | Some t -> Ok t
    | None -> Error (Unknown name)
end

module Format = struct
  type t =
    | Single_track
    | Simultaneous_tracks of int
    | Sequential_tracks of int

  let to_string = function
    | Single_track -> "Single_track"
    | Simultaneous_tracks n -> sprintf "(Simultaneous_tracks %d)" n
    | Sequential_tracks n -> sprintf "(Sequential_tracks %d)" n

  let num_tracks = function
    | Single_track -> 1
    | Simultaneous_tracks n | Sequential_tracks n -> n
end

module Division = struct
  type time_code = { smpte_format : int; ticks_per_frame : int }
  type t = Ticks_per_quarter_note of int | Time_code of time_code

  let to_string = function
    | Ticks_per_quarter_note n -> sprintf "(Ticks_per_quarter_note %d)" n
    | Time_code { smpte_format; ticks_per_frame } ->
        sprintf "(Time_code ((smpte_format %d) (ticks_per_frame %d)))"
          smpte_format ticks_per_frame

  let of_raw_int16 i =
    let payload = i land lnot (1 lsl 15) in
    if i land (1 lsl 15) == 0 then Ticks_per_quarter_note payload
    else
      let negative_smpte_format = payload lsr 8 in
      let ticks_per_frame = payload land 255 in
      let smpte_format = -negative_smpte_format + 1 in
      Time_code { smpte_format; ticks_per_frame }
end

module Header = struct
  module Raw = struct
    type t = { format_ : int; ntrks : int; division : int }

    let parse =
      let open Byte_array_parser in
      let+ format_ = int16be and+ ntrks = int16be and+ division = int16be in
      { format_; ntrks; division }
  end

  type t = { format_ : Format.t; division : Division.t }

  let to_string { format_; division } =
    sprintf "((format_ %s) (division %s))" (Format.to_string format_)
      (Division.to_string division)

  let of_raw { Raw.format_; ntrks; division } =
    let format_ =
      match format_ with
      | 0 ->
          if ntrks != 1 then
            raise
              (Parse_exception
                 (sprintf "expected 1 track for Single_track format but got %d"
                    ntrks));
          Format.Single_track
      | 1 -> Format.Simultaneous_tracks ntrks
      | 2 -> Format.Sequential_tracks ntrks
      | _ ->
          raise
            (Parse_exception
               (sprintf "unexpected format field in header: %d" format_))
    in
    let division = Division.of_raw_int16 division in
    { format_; division }

  let parse = Byte_array_parser.(Raw.parse >>| of_raw)
end

module Channel_voice_message = struct
  type note_event = { note : int; velocity : int }
  type polyphonic_key_pressure = { note : int; pressure : int }
  type control_change = { controller : int; value : int }
  type program_change = { program : int }
  type channel_pressure = { pressure : int }
  type pitch_wheel_change = { signed_value : int }

  type message =
    | Note_off of note_event
    | Note_on of note_event
    | Polyphonic_key_pressure of polyphonic_key_pressure
    | Control_change of control_change
    | Program_change of program_change
    | Channel_pressure of channel_pressure
    | Pitch_wheel_change of pitch_wheel_change

  type t = { channel : int; message : message }

  let note_event_to_string { note; velocity } =
    sprintf "((note %d) (velocity %d))" note velocity

  let polyphonic_key_pressure_to_string { note; pressure } =
    sprintf "((note %d) (pressure %d))" note pressure

  let control_change_to_string { controller; value } =
    sprintf "((controller %d) (value %d))" controller value

  let program_change_to_string { program } = sprintf "((program %d))" program

  let channel_pressure_to_string { pressure } =
    sprintf "((pressure %d))" pressure

  let pitch_wheel_change_to_string { signed_value } =
    sprintf "((signed_value %d))" signed_value

  let message_to_string = function
    | Note_off note_event ->
        sprintf "(Note_off %s)" (note_event_to_string note_event)
    | Note_on note_event ->
        sprintf "(Note_on %s)" (note_event_to_string note_event)
    | Polyphonic_key_pressure polyphonic_key_pressure ->
        sprintf "(Polyphonic_key_pressure %s)"
          (polyphonic_key_pressure_to_string polyphonic_key_pressure)
    | Control_change control_change ->
        sprintf "(Control_change %s)" (control_change_to_string control_change)
    | Program_change program_change ->
        sprintf "(Program_change %s)" (program_change_to_string program_change)
    | Channel_pressure channel_pressure ->
        sprintf "(Channel_pressure %s)"
          (channel_pressure_to_string channel_pressure)
    | Pitch_wheel_change pitch_wheel_change ->
        sprintf "(Pitch_wheel_change %s)"
          (pitch_wheel_change_to_string pitch_wheel_change)

  let to_string { channel; message } =
    sprintf "((channel %d) (message %s))" channel (message_to_string message)

  let parse status =
    if status < 0 || status > 255 then raise (Parse_exception "Expected byte");
    if status < 128 then
      raise (Parse_exception "Expected most significant bit to be 1");
    let open Byte_array_parser in
    (* bits 4,5,6 *)
    let message_type_identifier = (status lsr 4) land 0x7 in
    let channel = status land 0xF in
    let+ message =
      match message_type_identifier with
      | 0 ->
          let+ note = byte_msb0 and+ velocity = byte_msb0 in
          Note_off { note; velocity }
      | 1 ->
          let+ note = byte_msb0 and+ velocity = byte_msb0 in
          Note_on { note; velocity }
      | 2 ->
          let+ note = byte_msb0 and+ pressure = byte_msb0 in
          Polyphonic_key_pressure { note; pressure }
      | 3 ->
          let+ controller = byte_msb0 and+ value = byte_msb0 in
          Control_change { controller; value }
      | 4 ->
          let+ program = byte_msb0 in
          Program_change { program }
      | 5 ->
          let+ pressure = byte_msb0 in
          Channel_pressure { pressure }
      | 6 ->
          let+ low_bits = byte_msb0 and+ high_bits = byte_msb0 in
          let value_14_bits = low_bits lor (high_bits lsl 7) in
          let signed_value = value_14_bits - 0x2000 in
          Pitch_wheel_change { signed_value }
      | other ->
          raise
            (Parse_exception
               (sprintf "Unexpected message type identifier: %d" other))
    in
    { channel; message }
end

module System_message = struct
  type system_exclusive = { manufacturer_id : int; payload : int list }

  let system_exclusive_to_string { manufacturer_id; payload } =
    sprintf "((manufacturer_id %d) (payload (%s)))" manufacturer_id
      (String.concat " " (List.map string_of_int payload))

  let system_exclusive_parse =
    let system_exclusive_end = 0b11110111 in
    let open Byte_array_parser in
    let rec loop acc =
      let* byte = byte in
      if byte == system_exclusive_end then return acc
      else if byte land (1 lsl 7) <> 0 then
        raise
          (Parse_exception
             "Most significant bit is 1 but byte does not encode 'System \
              Exclusive End'")
      else loop (byte :: acc)
    in
    let+ manufacturer_id = byte_msb0 and+ payload = loop [] >>| List.rev in
    { manufacturer_id; payload }

  type t =
    | System_exclusive of system_exclusive
    | Song_position_pointer of int
    | Song_select of int
    | Tune_request
    | Timing_clock
    | Start
    | Continue
    | Stop
    | Active_sensing
    | Reset
    | Undefined of int

  let to_string = function
    | System_exclusive system_exclusive ->
        sprintf "(System_exclusive %s)"
          (system_exclusive_to_string system_exclusive)
    | Song_position_pointer song_position_pointer ->
        sprintf "(Song_position_pointer %d)" song_position_pointer
    | Song_select song_select -> sprintf "(Song_select %d)" song_select
    | Tune_request -> "Tune_request"
    | Timing_clock -> "Timing_clock"
    | Start -> "Start"
    | Continue -> "Continue"
    | Stop -> "Stop"
    | Active_sensing -> "Active_sensing"
    | Reset -> "Reset"
    | Undefined undefined -> sprintf "(Undefined %d)" undefined

  let parse status =
    if status < 0 || status > 255 then raise (Parse_exception "Expected byte");
    if status lsr 4 <> 0xF then
      raise (Parse_exception "Expected top 4 bits to be 0xF");
    let message_type_identifier = status land 0xF in
    let open Byte_array_parser in
    match message_type_identifier with
    | 1 | 4 | 5 | 9 | 13 -> return (Undefined message_type_identifier)
    | 0 ->
        let+ system_exclusive = system_exclusive_parse in
        System_exclusive system_exclusive
    | 2 ->
        let+ low = byte_msb0 and+ high = byte_msb0 in
        let value_14_bits = low lor (high lsl 7) in
        Song_position_pointer value_14_bits
    | 3 ->
        let+ song_select = byte_msb0 in
        Song_select song_select
    | 6 -> return Tune_request
    | 7 ->
        raise
          (Parse_exception
             "Encountered 'System Exclusive End' without corresponding 'System \
              Exclusive'")
    | 8 -> return Timing_clock
    | 10 -> return Start
    | 11 -> return Continue
    | 12 -> return Stop
    | 14 -> return Active_sensing
    | 15 -> return Reset
    | other ->
        raise
          (Parse_exception
             (sprintf "Unexpected message type identifier: %d" other))
end

module Meta_event = struct
  type other = { type_index : int; contents : char array }
  type t = End_of_track | Other of other

  let to_string = function
    | End_of_track -> "End_of_track"
    | Other { type_index; contents = _ } ->
        sprintf "(Other ((type_index %d) (contents ...)))" type_index

  let parse =
    let open Byte_array_parser in
    let* type_index, length = both byte byte in
    match type_index with
    | 0x2F -> return End_of_track
    | _ ->
        let+ contents = n_bytes length in
        Other { type_index; contents }
end

module Message = struct
  type t =
    | Channel_voice_message of Channel_voice_message.t
    | System_message of System_message.t
    | Meta_event of Meta_event.t

  let to_string = function
    | Channel_voice_message channel_voice_message ->
        sprintf "(Channel_voice_message %s)"
          (Channel_voice_message.to_string channel_voice_message)
    | System_message system_message ->
        sprintf "(System_message %s)" (System_message.to_string system_message)
    | Meta_event meta_event ->
        sprintf "(Meta_event %s)" (Meta_event.to_string meta_event)

  let parse status =
    let open Byte_array_parser in
    if status < 0 || status > 255 then raise (Parse_exception "Expected byte");
    if status < 128 then
      raise (Parse_exception "Expected most significant bit to be 1");
    if status == 255 then
      Meta_event.parse >>| fun meta_event -> Meta_event meta_event
    else
      let message_type_identifier = (status lsr 4) land 0x7 in
      if message_type_identifier == 7 then
        let+ system_message = System_message.parse status in
        System_message system_message
      else
        let+ channel_voice_message = Channel_voice_message.parse status in
        Channel_voice_message channel_voice_message
end

module Event = struct
  type t = { delta_time : int; message : Message.t }

  let to_string { delta_time; message } =
    let message_string = Message.to_string message in
    sprintf "((delta_time %d) (message %s))" delta_time message_string

  let parse_result running_status =
    let open Byte_array_parser in
    let* delta_time = variable_length_quantity and+ next_byte = peek_byte in
    let* status =
      if next_byte >= 128 then
        let+ () = skip 1 in
        next_byte
      else
        match running_status with
        | Some running_status -> return running_status
        | None -> raise (Parse_exception "First event in track lacks status")
    in
    let+ message = Message.parse status in
    ({ delta_time; message }, `Status status)
end

module Track = struct
  type t = Event.t list

  let to_string t =
    sprintf "(%s)" (String.concat "\n" (List.map Event.to_string t))

  let parse length =
    let open Byte_array_parser in
    let rec loop acc rem_length running_status =
      if rem_length == 0 then return acc
      else if rem_length < 0 then
        raise
          (Parse_exception
             "Last event in track extends beyond the track boundary")
      else
        let* event, `Status running_status =
          Event.parse_result running_status
        in
        match event.message with
        | Meta_event End_of_track -> return (event :: acc)
        | _ ->
            (loop [@tailcall]) (event :: acc) (rem_length - 1)
              (Some running_status)
    in
    loop [] length None >>| List.rev
end

module Chunk = struct
  type t = Header of Header.t | Track of Track.t

  let parse_result =
    let open Byte_array_parser in
    let* type_result, length = both Chunk_type.parse_result int32be in
    match type_result with
    | Ok Header ->
        let+ header = Header.parse in
        Ok (Header header)
    | Ok Track ->
        let+ track = Track.parse length in
        Ok (Track track)
    | Error unknown ->
        let+ () = skip length in
        Error unknown
end

module Data = struct
  type t = { header : Header.t; tracks : Track.t list }

  let to_string { header; tracks } =
    sprintf "((header %s)\n(tracks (%s)))" (Header.to_string header)
      (String.concat "\n" (List.map Track.to_string tracks))

  let parse =
    let open Byte_array_parser in
    let+ all_chunk_results = repeat_until_end_exact Chunk.parse_result in
    let t =
      match all_chunk_results with
      | first :: rest ->
          let header =
            match first with
            | Ok (Header header) -> header
            | _ -> raise (Parse_exception "First chunk was not header")
          in
          let tracks =
            List.filter_map
              (function
                | Ok (Chunk.Header _) ->
                    Printf.eprintf "Second header found after first chunk\n";
                    None
                | Ok (Track track) -> Some track
                | Error (Unknown unknown_chunk_type) ->
                    Printf.eprintf "Unknown chunk type: %s\n" unknown_chunk_type;
                    None)
              rest
          in
          { header; tracks }
      | _ -> raise (Parse_exception "No chunks found")
    in
    let num_tracks_according_to_header = Format.num_tracks t.header.format_ in
    let num_tracks_found = List.length t.tracks in
    if num_tracks_according_to_header <> num_tracks_found then
      Printf.eprintf
        "Header implies there should be %d tracks but found %d tracks instead\n"
        num_tracks_according_to_header num_tracks_found;
    t
end

module File_reader = struct
  type t = { path : string }

  let of_path path = { path }

  let read_byte_array t =
    let channel = open_in_bin t.path in
    let rec loop acc =
      match input_char channel with
      | byte -> (loop [@tailcall]) (byte :: acc)
      | exception End_of_file -> List.rev acc
    in
    let byte_list = loop [] in
    close_in channel;
    Array.of_list byte_list

  let read t =
    let byte_array = read_byte_array t in
    Byte_array_parser.run Data.parse byte_array
end
