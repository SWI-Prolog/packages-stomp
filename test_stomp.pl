/*  Part of SWI-Prolog

    Author:        Jan Wielemaker
    E-mail:        jan@swi-prolog.org
    WWW:           http://www.swi-prolog.org
    Copyright (c)  2026, SWI-Prolog Solutions b.v.
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions
    are met:

    1. Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.

    2. Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in
       the documentation and/or other materials provided with the
       distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
    COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
    POSSIBILITY OF SUCH DAMAGE.
*/


:- module(test_stomp,
          [ test_stomp/0
          ]).
:- use_module(library(plunit)).
:- use_module(library(socket)).
:- use_module(library(stomp)).

/** <module> Test the STOMP client

Tests the STOMP client against a minimal fake broker that accepts the
CONNECT frame, replies CONNECTED and sends a canned sequence of frames.
*/

test_stomp :-
    run_tests([ stomp
              ]).

%!  with_broker(+Frames, -Received) is det.
%
%   Connect to a fake broker that sends Frames (a list of strings) and
%   collect the callbacks in Received.  The last frame sent is a message
%   with body `"done"`.

with_broker(Frames, Received) :-
    message_queue_create(Q),
    tcp_socket(S),
    tcp_bind(S, localhost:Port),
    tcp_listen(S, 1),
    append(Frames,
           ["MESSAGE\ncontent-type:text/plain\ncontent-length:4\n\ndone\u0000\n"],
           AllFrames),
    thread_create(serve(S, AllFrames), Broker, []),
    stomp_connection(localhost:Port, '/', _{}, collect(Q), C),
    call_cleanup(
        ( stomp_connect(C),
          collect(Q, Received)
        ),
        ( stomp_destroy_connection(C),
          thread_join(Broker, _),
          tcp_close_socket(S),
          message_queue_destroy(Q)
        )).

serve(S, Frames) :-
    tcp_accept(S, C, _),
    tcp_open_socket(C, Pair),
    stream_pair(Pair, In, Out),
    set_stream(In, encoding(utf8)),
    set_stream(Out, encoding(utf8)),
    read_string(In, "\u0000", "", _, _Connect),
    format(Out, "CONNECTED\nversion:1.2\n\n\u0000\n", []),
    forall(member(F, Frames), format(Out, "~s", [F])),
    flush_output(Out),
    read_string(In, "\u0000", "", _, _), % wait for client to close
    close(Pair, [force(true)]).

collect(Q, Cmd, _Conn, Header, Body) :-
    (   Cmd == heartbeat
    ->  true
    ;   thread_send_message(Q, frame(Cmd, Header, Body))
    ).

collect(Q, Received) :-
    (   thread_get_message(Q, frame(Cmd, _Header, Body), [timeout(10)])
    ->  (   Cmd == message, Body == "done"
        ->  Received = []
        ;   Cmd == disconnected
        ->  Received = [disconnected]
        ;   Cmd == connected
        ->  collect(Q, Received)
        ;   Received = [Cmd-Body|More],
            collect(Q, More)
        )
    ;   Received = [timeout]
    ).

:- begin_tests(stomp).

test(message, R == [message-"abc"]) :-
    with_broker(["MESSAGE\ncontent-type:text/plain\ncontent-length:3\n\nabc\u0000\n"],
                R).
test(json, A == 1) :-
    with_broker(["MESSAGE\ncontent-type:application/json; charset=utf-8\n\c
                  content-length:7\n\n{\"a\":1}\u0000\n"],
                [message-Dict]),
    A = Dict.a.
test(bad_json, R == [message-"{x:"]) :-
    with_broker(["MESSAGE\ncontent-type:application/json\ncontent-length:3\n\n{x:\u0000\n"],
                R).
test(no_content_length, R == [error-"some t\u00e9xt"]) :-
    with_broker(["ERROR\nmessage:bad\n\nsome t\u00e9xt\u0000\n"],
                R).
test(content_length, R == [disconnected]) :-
    with_broker(["MESSAGE\ncontent-type:text/plain\ncontent-length:-1\n\nxy\u0000\n"],
                R).
test(wrong_length, R == [disconnected]) :-
    with_broker(["MESSAGE\ncontent-type:text/plain\ncontent-length:1\n\nxy\u0000\n"],
                R).
test(escape_header, S == "x\\ny:a\\rb\\c\n") :-
    with_output_to(string(S),
                   stomp:send_header_line(current_output, 'x\ny'-"a\rb:")).

:- end_tests(stomp).
