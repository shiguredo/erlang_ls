-module(efmt_formatter).

-behaviour(rebar3_formatter).

-export([init/2, format_file/3]).

-include_lib("kernel/include/logger.hrl").

-record(?MODULE, {}).

-type state() :: #?MODULE{}.

-spec init(rebar3_formatter:opts(), unused) -> state().
init(_Opts, _) ->
    #?MODULE{}.

-spec format_file(file:filename_all(), state(), rebar3_formatter:opts()) ->
    rebar3_formatter:result().
format_file(File, _State, Opts) ->
    case Opts of
        #{action := verify} ->
            error(not_implemented);
        _ ->
            Path = filename:join(filename:absname(maps:get(output_dir, Opts)), File),

            ok = filelib:ensure_dir(Path),
            {ok, _} = file:copy(File, Path),
            case execute_command(["--write", Path]) of
                {ok, _} ->
                    changed;
                {error, Output} ->
                    ?LOG_WARNING("[efmt] Failed to format ~p: output=~s", [File, Output]),
                    unchanged
            end
    end.

-spec find_command() -> {ok, string(), [string()], [term()]} | {error, binary()}.
find_command() ->
    case os:find_executable("efmt") of
        false ->
            case project_root_dir() of
                {error, Reason} ->
                    {error, Reason};
                {ok, RootDir} ->
                    case os:find_executable(filename:join(RootDir, "_build/default/plugins/rebar3_efmt/priv/efmt")) of
                        false ->
                            case os:find_executable("rebar3") of
                                false ->
                                    case os:find_executable(filename:join(RootDir, "rebar3")) of
                                        false ->
                                            {error, <<"both rebar3 and efmt commands are not found">>};
                                        Path ->
                                            {ok, Path, ["efmt"], [{cd, RootDir}]}
                                    end;
                                Path ->
                                    {ok, Path, ["efmt"], [{cd, RootDir}]}
                            end;
                        Path ->
                            {ok, Path, [], []}
                    end
            end;
        Path ->
            {ok, Path, [], []}
    end.

-spec execute_command([string()]) -> {ok | error, binary()}.
execute_command(Args) ->
    case find_command() of
        {error, Reason} ->
            {error, Reason};
        {ok, Path, Args0, Options0} ->
            Port = erlang:open_port({spawn_executable, Path}, [{args, Args0 ++ Args}, exit_status | Options0]),
            collect_command_output(Port, [])
    end.

-spec collect_command_output(port(), iolist()) -> {ok | error, binary()}.
collect_command_output(Port, Output) ->
    receive
        {Port, {data, Data}} ->
            collect_command_output(Port, [Output | Data]);
        {Port, {exit_status, 0}} ->
            {ok, list_to_binary(Output)};
        {Port, {exit_status, _}} ->
            {error, list_to_binary(Output)}
    after 60000 ->
        {erorr, <<"timeout">>}
    end.

-spec project_root_dir() -> {ok, string()} | {error, binary()}.
project_root_dir() ->
    case file:get_cwd() of
        {error, Reason} ->
            {error, iolist_to_binary(io_lib:format("`file:get_cwd/0` failed: reason=~p", [Reason]))};
        {ok, Dir} ->
            project_root_dir(Dir)
    end.

-spec project_root_dir(string()) -> {ok, string()} | {error, binary()}.
project_root_dir("/") ->
    {error, <<"rebar.config is not found">>};
project_root_dir(Dir) ->
    case filelib:is_file(filename:join(Dir, "rebar.config")) of
        true ->
            {ok, Dir};
        false ->
            project_root_dir(filename:dirname(Dir))
    end.
