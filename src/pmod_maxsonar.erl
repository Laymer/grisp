% @doc
% <a href="https://store.digilentinc.com/pmodmaxsonar-maxbotix-ultrasonic-range-finder/">
% Pmod MAXSONAR
% </a>
% module.
%
% The Pmod MAXSONAR cyclically sends measurements via the UART interface.
% This module converts and stores the latest measurement.
%
% Start the driver with
%  ```
%  1> grisp:add_device(uart, pmod_maxsonar).
%  '''
% @end
-module(pmod_maxsonar).

-behaviour(gen_server).

% API
-export([start_link/2]).
-export([get/0]).
-export([get_single/0]).

% Callbacks
-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([code_change/3]).
-export([terminate/2]).

%--- Records -------------------------------------------------------------------

-record(state, {port, last_val, txd_pin_state}).

%--- API -----------------------------------------------------------------------

% @private
start_link(Slot, _Opts) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Slot, []).

% @doc Get the latest measured distance in inches.
-spec get() -> integer().
get() ->
    gen_server:call(?MODULE, get_value).
% @doc Get the latest measured distance in inches.
-spec get_single() -> integer().
get_single() ->
    gen_server:call(?MODULE, get_single_value).

%--- Callbacks -----------------------------------------------------------------

% @private
init(Slot = uart) ->
    Port = open_port({spawn_driver, "grisp_termios_drv"}, [binary]),
    grisp_devices:register(Slot, ?MODULE),
    grisp_gpio:configure(uart_2_txd, output_0),
    {ok, #state{
        port = Port
        , txd_pin_state = output_0
        , last_val = undefined}}.

% @private
handle_call(get_value, _From, #state{last_val = Val} = State) ->
    {reply, Val, State};
% @private
handle_call(get_single_value, _From, #state{last_val = Val, txd_pin_state = Txd} = State) ->
    Single = case Txd =:= output_0 of
        true -> %% first measurement
            grisp_gpio:configure(uart_2_txd, output_1),
            timer:sleep(50),
            pmod_maxsonar:get();
        _ ->
            case Val =:= undefined of
                true ->
                    grisp_gpio:configure(uart_2_txd, output_1),
                    timer:sleep(50),
                    pmod_maxsonar:get();
                false ->
                    pmod_maxsonar:get()
            end
    end,
    grisp_gpio:configure(uart_2_txd, output_0),
    {reply
        , Single
        , State#state{last_val = Single, txd_pin_state = output_0}
        , 5000}.

% @private
handle_cast(Request, _State) -> error({unknown_cast, Request}).

% @private
handle_info({Port, {data, Data}}, #state{port = Port} = State) ->
    case Data of
        % Format of response is 'Rxxx\n' where xxx is the decimal
        % representation of the measured range in inches (2.54cm)
        % (left-padded with zeros - so there are always three digits)
        <<$R, D1, D2, D3, $\n>> when $0 =< D1, D1 =< $9,
                                      $0 =< D2, D2 =< $9,
                                      $0 =< D3, D3 =< $9 ->
            % Val is given in inches
            Val = (D1 - $0) * 100 + (D2 - $0) * 10 + (D3 - $0),
            {noreply, State#state{last_val = Val}};
        % Sometimes for no obvious reason we receive
        % a different value from the sonar.
        % Instead of $R we get two garbage characters
        <<_, _, D1, D2, D3, $\n>> when $0 =< D1, D1 =< $9,
                                      $0 =< D2, D2 =< $9,
                                      $0 =< D3, D3 =< $9 ->
            % Val is given in inches
            Val = (D1 - $0) * 100 + (D2 - $0) * 10 + (D3 - $0),
            {noreply, State#state{last_val = Val}};
        _ ->
            {noreply, State}
    end.



% @private
code_change(_OldVsn, State, _Extra) -> {ok, State}.

% @private
terminate(_Reason, _State) -> ok.
