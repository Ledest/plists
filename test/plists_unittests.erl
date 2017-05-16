-module(plists_unittests).

-export([run/0]).

setup_network() ->
    Node = lists:flatten(io_lib:format("second_node_~2..0B~2..0B~2..0B@localhost", tuple_to_list(time()))),
    open_port({spawn, lists:concat(["erl -pa ../ebin -noshell -sname ", Node, " -setcookie ", erlang:get_cookie()])},
              []),
    wait_until_running(list_to_atom(Node)).

wait_until_running(Node) ->
    case net_adm:ping(Node) of
        pong -> Node;
        pang ->
            timer:sleep(20),
            wait_until_running(Node)
    end.

close_network(Node) -> rpc:call(Node, init, stop, []).

run() ->
    Node = setup_network(),
    try
        tests(Node)
    catch never -> never % junk so we can have after
    after close_network(Node)
    end.

tests(Node) ->
    do_tests(1),
    do_tests(4),
    do_tests({processes, 2}),
    do_tests([4, {processes, 2}]),
    do_tests({processes, schedulers}),
    do_tests({timeout, 4000}),
    do_tests({nodes, [{node(), 2}, node(), {node(), schedulers}]}),
    do_tests({nodes, [{Node, 2}, Node, {Node, schedulers}]}),
    do_tests([{nodes, [{node(), 2}, Node]}, {timeout, 4000}, 4]),
    io:format("Ignore the ERROR REPORTs above, they are supposed to be there.~n"),
    io:format("all tests passed :)~n").

do_tests(Malt) ->
    io:format("Testing with malt: ~p~n", [Malt]),
    test_mapreduce(Malt),
    test_all(Malt),
    test_any(Malt),
    test_filter(Malt),
    test_fold(Malt),
    test_foreach(Malt),
    test_map(Malt),
    test_partition(Malt),
    test_sort(Malt),
    test_usort(Malt),
    check_leftovers(),
    do_error_tests(Malt),
    io:format("tests passed :)~n").

do_error_tests(Malt) ->
    {'EXIT', {badarith, _}} = (catch plists:map(fun(X) -> 1/X end, [1,2,3,0,4,5,6], Malt)),
    check_leftovers(),
    if
        is_list(Malt) -> MaltList = Malt;
        true -> MaltList = [Malt]
    end,
    MaltTimeout0 = [{timeout, 0}|MaltList],
    {'EXIT', timeout} = (catch test_mapreduce(MaltTimeout0)),
    check_leftovers(),
    MaltTimeout40 = [{timeout, 40}|MaltList],
    {'EXIT', timeout} = (catch plists:foreach(fun(_X) -> timer:sleep(1000) end, [1,2,3], MaltTimeout40)),
    check_leftovers(),
    'tests_passed :)'.

check_leftovers() ->
    receive
        {'EXIT', _, _} ->
            % plists doesn't start processes with spawn_link, so we
            % know these aren't our fault.
            check_leftovers();
        M ->
            io:format("Leftover messages:~n~p~n", [M]),
            print_leftovers()
        after 0 -> nil
    end.

print_leftovers() ->
    receive
        M ->
            io:format("~p~n", [M]),
            print_leftovers()
    after 0 -> exit(leftover_messages)
    end.

test_mapreduce(Malt) ->
    Ans = plists:mapreduce(fun(X) -> [{Y, X} || Y <- lists:seq(1, X - 1)] end, [2,3,4,5], Malt),
    % List1 consists of [2,3,4,5]
    List1 = dict:fetch(1, Ans),
    Fun1 = fun(X) -> lists:member(X, List1) end,
    true = lists:all(Fun1, [2,3,4,5]),
    false = lists:any(Fun1, [1,6]),
    % List3 consists of [4,5]
    List3 = dict:fetch(3, Ans),
    Fun3 = fun(X) -> lists:member(X, List3) end,
    true = lists:all(Fun3, [4,5]),
    false = lists:any(Fun3, [1,2,3,6]),
    Text = "how many of each letter",
    TextAns = plists:mapreduce(fun(X) -> {X, 1} end, Text, Malt),
    TextAns2 = dict:map(fun(_X, List) -> lists:sum(List) end, TextAns),
    lists:foreach(fun({X, Y}) -> X = dict:fetch(Y, TextAns2) end, [{3, $e}, {2, $h}, {1, $m}]).

test_all(Malt) ->
    true = plists:all(fun even/1, [2,4,6,8], Malt),
    false = plists:all(fun even/1, [2,4,5,8], Malt).

even(X) -> X rem 2 =:= 0.

test_any(Malt) ->
    true = plists:any(fun even/1, [1,2,3,4,5], Malt),
    false = plists:any(fun even/1, [1,3,5,7], Malt).

test_filter(Malt) ->
    [2,4,6] = plists:filter(fun even/1, [1,2,3,4,5,6], Malt).

test_fold(Malt) ->
    15 = plists:fold(fun erlang:'+'/2, 0, [1,2,3,4,5], Malt),
    Fun = fun(X, A) ->
              case X * X of
                  X2 when X2 > A -> X2;
                  _ -> A
              end
          end,
    Fuse = fun (A1, A2) when A1 > A2 -> A1;
               (_A1, A2) -> A2
           end,
    List = lists:seq(-5, 4),
    25 = plists:fold(Fun, Fuse, -10000, List, Malt),
    25 = plists:fold(Fun, {recursive, Fuse}, -10000, List, Malt).

test_foreach(_Malt) -> whatever.

test_map(Malt) ->
    [2,4,6,8,10] = plists:map(fun(X) -> X * 2 end, [1,2,3,4,5], Malt),
    % edge cases
    [2] = plists:map(fun (X) -> X * 2 end, [1], Malt),
    [] = plists:map(fun (X) -> X * 2 end, [], Malt).

test_partition(Malt) ->
    {[2,4,6], [1,3,5]} = plists:partition(fun even/1, [1,2,3,4,5,6], Malt).

test_sort(Malt) ->
    [1,2,2,3,4,5,5] = plists:sort(fun erlang:'=<'/2, [2,4,5,1,2,5,3], Malt),
    % edge cases
    [1] = plists:sort(fun erlang:'=<'/2, [1], Malt),
    [] = plists:sort(fun erlang:'=<'/2, [], Malt).

test_usort(Malt) ->
    [1,2,3,4,5] = plists:usort(fun erlang:'=<'/2, [2,4,5,1,2,5,3], Malt),
    [1,2,3,4,5] = plists:usort(fun erlang:'=<'/2, [2,4,5,1,2,5,3], Malt).
