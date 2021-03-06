%% Copyright (c) 2021 Exograd SAS.
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

-module(mlog).

-export([install/0]).

-spec install() -> ok.
install() ->
  %% We have to both update the system configuration and modify the logger
  %% dynamically. Some applications such as the Rebar3 shell plugin will use
  %% the system configuration to reset the logger, and this unfortunately
  %% cannot be disabled.
  remove_all_handlers(),
  (PrimaryConfig = #{level := Level}) = primary_config(),
  DefaultHandler = default_handler(),
  DebugHandler = debug_handler(),
  application:set_env(kernel, logger_level, Level),
  application:set_env(kernel, logger,
                      [{handler, default, mlog_handler, DefaultHandler},
                       {handler, debug, mlog_handler, DebugHandler}]),
  ok = logger:set_primary_config(PrimaryConfig),
  ok = logger:add_handler(default, mlog_handler, DefaultHandler),
  ok = logger:add_handler(debug, mlog_handler, DebugHandler),
  ok.

-spec device() -> mlog_handler:device().
device() ->
  application:get_env(mlog, device, standard_error).

-spec formatter_config() -> mlog_formatter:config().
formatter_config() ->
  application:get_env(mlog, formatter, #{color => true}).

-spec debug_filters() -> [logger:filter()].
debug_filters() ->
  application:get_env(mlog, debug_filters, []).

-spec level() -> logger:level().
level() ->
  application:get_env(mlog, level, debug).

-spec metadata() -> map().
metadata() ->
  application:get_env(mlog, metadata, #{}).

-spec remove_all_handlers() -> ok.
remove_all_handlers() ->
  lists:foreach(fun (#{id := Id}) ->
                    logger:remove_handler(Id)
                end, logger:get_handler_config()).

-spec primary_config() -> logger:primary_config().
primary_config() ->
  #{level => level(),
    metadata => metadata(),
    filter_default => log,
    filters => []}.

-spec default_handler() -> logger:handler_config().
default_handler() ->
  #{config => #{device => device()},
    level => info,
    filter_default => log,
    filters =>
      [{progress,
        {fun logger_filters:progress/2, stop}},
       {remote_group_leader,
        {fun logger_filters:remote_gl/2, stop}},
       {gen_server,
        {fun mlog_filters:gen_server_report/2, stop}}],
    formatter => {mlog_formatter, formatter_config()}}.

-spec debug_handler() -> logger:handler_config().
debug_handler() ->
  MainFilter = {debug, {fun logger_filters:level/2,
                        {stop, neq, debug}}},
  ExtraFilters = debug_filters(),
  #{config => #{device => device()},
    level => debug,
    filter_default => stop,
    filters => [MainFilter | ExtraFilters],
    formatter => {mlog_formatter, formatter_config()}}.
