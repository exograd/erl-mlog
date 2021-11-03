%% Copyright (c) 2021 Bryan Frimin <bryan@frimin.fr>.
%%
%% Permission to use, copy, modify, and/or distribute this software for any
%% purpose with or without fee is hereby granted, provided that the above
%% copyright notice and this permission notice appear in all copies.
%%
%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
%% SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR
%% IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

-module(mlog_rfc5424_formatter).

-include_lib("kernel/include/inet.hrl").

-export([format/4]).

-type config() :: mlog_formatter:config().

-spec format(unicode:chardata(), logger:level(), logger:metadata(), config())
            -> unicode:chardata().
format(Bin, Level, Metadata, Config) ->
  lists:join($\s, [header(Level, Metadata, Config),
                   structured_data(Metadata),
                   msg(Bin)]).

% https://datatracker.ietf.org/doc/html/rfc5424#section-6.2
-spec header(logger:level(), logger:metadata(), config()) -> iodata().
header(Level, Metadata, Config) ->
  lists:join($\s, [pri(Level), version(), timestamp(Metadata), hostname(),
                   app_name(Config), procid(), msgid(Metadata)]).

% https://datatracker.ietf.org/doc/html/rfc5424#section-6.2.1
-spec pri(logger:level()) -> iodata().
pri(L) ->
  PV = prival(L),
  [$<, integer_to_binary(PV), $>].

-spec prival(logger:level()) -> 0..191.
prival(L) ->
  facility_code() * 8 + severity_code(L).

% RFC: 5424
% Section: 6.2.1
% Table: 1
-spec facility_code() -> 16.
facility_code() -> 16. % local use 0

% RFC: 5424
% Section: 6.2.1
% Table: 2
-spec severity_code(logger:level()) -> 0..7.
severity_code(emergency) -> 0;
severity_code(alert) -> 1;
severity_code(critical) -> 2;
severity_code(error) -> 3;
severity_code(warning) -> 4;
severity_code(notice) -> 5;
severity_code(info) -> 6;
severity_code(debug) -> 7.

% https://datatracker.ietf.org/doc/html/rfc5424#section-6.2.2
-spec version() -> iodata().
version() -> "1".

% https://datatracker.ietf.org/doc/html/rfc5424#section-6.2.3
-spec timestamp(logger:metadata()) -> iodata().
timestamp(#{time := Time}) ->
  timestamp_1(Time);
timestamp(_) ->
  timestamp_1(erlang:system_time(microsecond)).

-spec timestamp_1(integer()) -> iodata().
timestamp_1(SysTime0) ->
  Options = [{unit, millisecond}, {offset, "Z"}],
  SysTime = SysTime0 div 1000,
  calendar:system_time_to_rfc3339(SysTime, Options).

% https://datatracker.ietf.org/doc/html/rfc5424#section-6.2.4
-spec hostname() -> iodata().
hostname() ->
  {ok, Hostname} = inet:gethostname(),
  case fqdn(Hostname) of
    {ok, FQDN} ->
      FQDN;
    error ->
      case static_addr(Hostname) of
        {ok, Addr} ->
          Addr;
        error ->
          Hostname
      end
  end.

-spec fqdn(string()) -> {ok, binary()} | error.
fqdn(Hostname) ->
  case inet:gethostbyname(Hostname) of
    {ok, #hostent{h_name = FQDN}} when is_atom(FQDN) ->
      {ok, atom_to_binary(FQDN)};
    {ok, #hostent{h_name = FQDN}} when is_list(FQDN) ->
      {ok, iolist_to_binary(FQDN)};
    {error, _} ->
      error
  end.

-spec static_addr(string()) -> {ok, iodata()} | error.
static_addr(Hostname) ->
  case inet:getaddr(Hostname, inet) of
    {ok, Addr4} ->
      case inet:ntoa(Addr4) of
        {error, _} ->
          error;
        Str ->
          {ok, Str}
      end;
    {error, _} ->
      case inet:getaddr(Hostname, inet6) of
        {ok, Addr6} ->
          case inet:ntoa(Addr6) of
            {error, _} ->
              error;
            Str ->
              {ok, Str}
          end;
        {error, _} ->
          error
      end
  end.

% https://datatracker.ietf.org/doc/html/rfc5424#section-6.2.5
-spec app_name(config()) -> iodata().
app_name(Config) ->
  maps:get(application_name, Config, [$-]).

% https://datatracker.ietf.org/doc/html/rfc5424#section-6.2.6
-spec procid() -> iodata().
procid() ->
  os:getpid().

% https://datatracker.ietf.org/doc/html/rfc5424#section-6.2.7
-spec msgid(logger:metadata()) -> iodata().
msgid(#{event := Event}) ->
  mlog_formatter:format_event(Event);
msgid(_) ->
  [$-].

% https://datatracker.ietf.org/doc/html/rfc5424#section-6.3
-spec structured_data(logger:metadata()) -> iodata().
structured_data(Metadata0) ->
  KS = [domain, time, error_logger, logger_formatter, report_cb, gl],
  Metadata = maps:without(KS, Metadata0),
  Domain = mlog_formatter:format_domain(maps:get(domain, Metadata0, [])),
  [sd_element("mlog@32473", Metadata#{domain => Domain})].

% https://datatracker.ietf.org/doc/html/rfc5424#section-6.3.1
-spec sd_element(string(), map()) -> iodata().
sd_element(Id, Metadata) ->
  Params = maps:fold(fun sd_param/3, [], Metadata),
  [$[, Id, $\s, lists:join($\s, Params), $]].

% https://datatracker.ietf.org/doc/html/rfc5424#section-6.3.3
-spec sd_param(atom(), term(), iodata()) -> iodata().
sd_param(Key, Value, Acc) when is_integer(Value) ->
  [[atom_to_binary(Key), $=, $", integer_to_binary(Value), $"] | Acc];
sd_param(Key, Value, Acc) when is_float(Value) ->
  [[atom_to_binary(Key), $=, $", float_to_binary(Value), $"] | Acc];
sd_param(Key, Value, Acc) when is_atom(Value) ->
  [[atom_to_binary(Key), $=, $", atom_to_binary(Value), $"] | Acc];
sd_param(Key, Value0, Acc) when is_binary(Value0) ->
  BOM = [16#EF, 16#BB, 16#BF],
  Value = unicode:characters_to_binary(escape(Value0, <<>>)),
  [[atom_to_binary(Key), $=, $", BOM, Value, $"] | Acc];
sd_param(_, _, Acc) ->
  Acc.

-spec escape(binary(), binary()) -> binary().
escape(<<$", Rest/binary>>, Acc) ->
  escape(Rest, <<Acc/binary, $\\, $">>);
escape(<<$\\, Rest/binary>>, Acc) ->
  escape(Rest, <<Acc/binary, $\\, $\\>>);
escape(<<$[, Rest/binary>>, Acc) ->
  escape(Rest, <<Acc/binary, $\\, $[>>);
escape(<<$], Rest/binary>>, Acc) ->
  escape(Rest, <<Acc/binary, $\\, $]>>);
escape(<<A, Rest/binary>>, Acc) ->
  escape(Rest, <<Acc/binary, A>>).

% https://datatracker.ietf.org/doc/html/rfc5424#section-6.4
-spec msg(iodata()) -> binary().
msg(Msg) ->
  BOM = [16#EF, 16#BB, 16#BF],
  unicode:characters_to_binary([BOM, Msg]).