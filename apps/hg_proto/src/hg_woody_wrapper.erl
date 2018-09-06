-module(hg_woody_wrapper).

%% Woody handler

-behaviour(woody_server_thrift_handler).

-export([handle_function/4]).
-export_type([handler_opts/0]).
-export_type([client_opts/0]).

-type handler_opts() :: #{
    handler => module(),
    default_handling_timeout => timeout(),
    user_identity => undefined | woody_user_identity:user_identity()
}.

-type client_opts() :: #{
    url            := woody:url(),
    transport_opts => [{_, _}]
}.

-define(DEFAULT_HANDLING_TIMEOUT, 30000).  % 30 seconds

%% Callbacks

-callback(handle_function(woody:func(), woody:args(), handler_opts()) ->
    term() | no_return()).

%% API

-export([call/3]).
-export([call/4]).
-export([raise/1]).


-spec handle_function(woody:func(), woody:args(), woody_context:ctx(), handler_opts()) ->
    {ok, term()} | no_return().

handle_function(Func, Args, Context0, #{handler := Handler} = Opts) ->
    Context = ensure_woody_deadline_set(Context0, Opts),
    hg_context:set(Context),
    try
        Result = Handler:handle_function(
            Func,
            Args,
            Opts
        ),
        {ok, Result}
    catch
        throw:Reason ->
            raise(Reason)
    after
        hg_context:cleanup()
    end.


-spec call(atom(), woody:func(), list()) ->
    term().

call(ServiceName, Function, Args) ->
    Opts = get_service(ServiceName),
    call(ServiceName, Function, Args, Opts).

-spec call(atom(), woody:func(), list(), client_opts()) ->
    term().

call(ServiceName, Function, Args, Opts) ->
    Service = get_service_modname(ServiceName),
    Context = hg_context:get(),
    woody_client:call(
        {Service, Function, Args},
        Opts#{event_handler => scoper_woody_event_handler},
        Context
    ).

-spec raise(term()) ->
    no_return().

raise(Exception) ->
    woody_error:raise(business, Exception).

%% Internal functions

get_service(ServiceName) ->
    construct_opts(maps:get(ServiceName, genlib_app:env(hellgate, services))).

construct_opts(Opts = #{url := Url}) ->
    Opts#{url := genlib:to_binary(Url)};
construct_opts(Url) ->
    #{url => genlib:to_binary(Url)}.

-spec get_service_modname(atom()) ->
    {module(), atom()}.

get_service_modname(ServiceName) ->
    hg_proto:get_service(ServiceName).

-spec ensure_woody_deadline_set(woody_context:ctx(), handler_opts()) ->
    woody_context:ctx().

ensure_woody_deadline_set(WoodyContext, Opts) ->
    case woody_context:get_deadline(WoodyContext) of
        undefined ->
            DefaultTimeout = maps:get(default_handling_timeout, Opts, ?DEFAULT_HANDLING_TIMEOUT),
            Deadline = woody_deadline:from_timeout(DefaultTimeout),
            woody_context:set_deadline(Deadline, WoodyContext);
        _Other ->
            WoodyContext
    end.
