-module(metrics_reader).
-behaviour(gen_server).

-include("metrics_reader.hrl").

%% API
-export([start_link/0,
         register/1,
         registered/0,
         deregister/1,
         metrics/0,
         console_metrics/0,
         console_metrics/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {format_module :: module(),
                node_tag      :: tag(),
                registry = sets:new()}).

-type state() :: #state{}.

%%%===================================================================
%%% API
%%%===================================================================

-spec start_link() -> gen_server_startlink_ret().
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

-spec register(list()) -> ok.
% TODO Allow client to specify tags
register(Names) when is_list(Names) ->
    gen_server:call(?SERVER, {register, Names});
register(Name) ->
    register([Name]).

-spec deregister(list()) -> ok.
deregister(Names) when is_list(Names) ->
    gen_server:call(?SERVER, {deregister, Names});
deregister(Name) ->
    deregister([Name]).

-spec registered() -> list().
registered() ->
    gen_server:call(?SERVER, registered).

-spec metrics() -> any().
metrics() ->
    gen_server:call(?SERVER, metrics).

%% The console passes in an empty args array, even if there are no args.
-spec console_metrics([]) -> any().
console_metrics([]) ->
    Metrics = gen_server:call(?SERVER, console_metrics),
    io:format("~s~n", [binary_to_list(Metrics)]).

-spec console_metrics() -> any().
console_metrics() ->
    console_metrics([]).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

-spec init([]) -> {ok, state()}.
init([]) ->
    FormatMod = metrics_reader_helper:opt(format, prometheus_format),
    NodeName = erlang:atom_to_binary(node(), utf8),
    {ok, #state{format_module = FormatMod,
                node_tag = {"node", NodeName}}}.

-spec handle_call(any(), any(), state()) -> {reply, term(), state()}.
handle_call({register, Names}, _From, State = #state{registry = Registry}) ->
    Registry1 = lists:foldl(fun sets:add_element/2, Registry, Names),
    {reply, ok, State#state{registry = Registry1}};

handle_call({deregister, Names}, _From, State = #state{registry = Registry}) ->
    Registry1 = lists:foldl(fun sets:del_element/2, Registry, Names),
    {reply, ok, State#state{registry = Registry1}};

handle_call(registered, _From, State = #state{registry = Registry}) ->
    Reply = sets:to_list(Registry),
    {reply, Reply, State};

handle_call(metrics, _From, State) ->
    Reply = format_metrics(State),
    {reply, Reply, State};

handle_call(console_metrics, _From,
            State = #state{format_module = FormatMod}) ->
    Lines = format_metrics(State),
    Reply = lists:foldl(fun FormatMod:combine_lines/2, <<>>, Lines),
    {reply, Reply, State};

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

-spec handle_cast(any(), state()) -> {noreply, state()}.
handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(any(), state()) -> {noreply, state()} |
                                     {stop, any(), state()}.
handle_info(_Info, State) ->
    {noreply, State}.

-spec terminate(any(), any()) -> ok.
terminate(_Reason, _State) ->
    ok.

-spec code_change(any(), state(), any()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

format_metrics(#state{format_module = FormatMod,
                      node_tag = NT,
                      registry = Registry}) ->
     [begin
          Spec = folsom_metrics:get_metric_info(Id),
          format_metric(FormatMod, NT, Spec)
      end || Id <- sets:to_list(Registry)].

format_metric(FormatMod, NT, [{N, [{type, histogram} | _Tags]}]) ->
    Hist = folsom_metrics:get_histogram_statistics(N),
    FormatMod:histogram(metric_name(N), [NT], Hist).

metric_name(B) when is_binary(B) ->
    [B];
metric_name(L) when is_list(L) ->
    [erlang:list_to_binary(L)];
metric_name(N1) when
      is_atom(N1) ->
    [a2b(N1)];
metric_name({N1, N2}) when
      is_atom(N1), is_atom(N2) ->
    [a2b(N1), a2b(N2)];
metric_name({N1, N2, N3}) when
      is_atom(N1), is_atom(N2), is_atom(N3) ->
    [a2b(N1), a2b(N2), a2b(N3)];
metric_name({N1, N2, N3, N4}) when
      is_atom(N1), is_atom(N2), is_atom(N3), is_atom(N4) ->
    [a2b(N1), a2b(N2), a2b(N3), a2b(N4)];
metric_name(T) when is_tuple(T) ->
    lists:flatten([metric_name(E) || E <- tuple_to_list(T)]).

a2b(A) ->
    erlang:atom_to_binary(A, utf8).
