%%%-------------------------------------------------------------------
%%% @author fu
%%% @copyright (C) 2019, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 19. 十一月 2019 9:51
%%%-------------------------------------------------------------------
-module(erlchat_date).
-author("fu").

%% API
-export([localTimeFormat/1]).
-export([localNowSeconds/0]).

localTimeFormat(Time) ->
  {{Year , Month , Day} , {Hour , Minute , Second}} = Time,
  list_to_binary(io_lib:format("~2..0w:~2..0w",
    [Hour,Minute])).

%% 返回当前时间的秒数
localNowSeconds() ->
  calendar:datetime_to_gregorian_seconds(calendar:now_to_local_time(erlang:now())) -
    calendar:datetime_to_gregorian_seconds({{1970,1,1}, {8,0,0}}).
