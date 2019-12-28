%%%-------------------------------------------------------------------
%%% @author fu
%%% @copyright (C) 2019, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 13. 十一月 2019 16:21
%%%-------------------------------------------------------------------
-module(erlchat_data).
-author("fu").
-include("erlchat_table.hrl").
-include_lib("stdlib/include/qlc.hrl").

%% API
-export([createTable/0]).
-export([add_tb_uchat_message/5]).
-export([query_tb_uchat_message/2]).
-export([server_url/0]).
-export([queryMsgSelect/4]).
-export([add_tb_uchat_msg/3]).
-export([syncJoinInfo/0 , acceptFriendApply/2 , updateHistoryInfo/0]).
-export([do/1 , doSort/1 , select_limit/3 , queryMsg/1 , updateMsgUnread/3 , unReadMsgNum/3 , totalUnread/1]).

%%查询用户历史聊天消息
queryMsg(UserId) ->
  try
    do(qlc:q([#{userid => X#tb_uchat_join_message.fromUserId , name => X#tb_uchat_join_message.fromName , avatar => X#tb_uchat_join_message.fromAvatar,
      company => X#tb_uchat_join_message.fromCompany , position => X#tb_uchat_join_message.fromPosition , unread => X#tb_uchat_join_message.unread ,
      lastTime => X#tb_uchat_join_message.lastTime , msgType => X#tb_uchat_join_message.lastMsgType , lastMessage => X#tb_uchat_join_message.lastMessage ,
      data => []} || X <- mnesia:table(tb_uchat_join_message),
      X#tb_uchat_join_message.toUserId =:= UserId]))
  catch
    _:_ -> []
  end.

queryMsgSelect(ToId , FromId , Start , Size) ->
  try
    Lists = doSort(qlc:q([X || X <- mnesia:table(tb_uchat_message) ,
      ((X#tb_uchat_message.from =:= FromId) and (X#tb_uchat_message.to =:= ToId) or (X#tb_uchat_message.from =:= ToId) and (X#tb_uchat_message.to =:= FromId))])),
    [Res|_] = lists:map(fun(Item) ->
          FromUserId = Item#tb_uchat_message.from,
          ToUserId = Item#tb_uchat_message.to,
          MsgId = Item#tb_uchat_message.msgId,
          Data = [#{userid => Uid , message => Msg , msgType => MsgType , addTime => AddTime , fromAvatar => avatarCheck(Uid , FromAvatar)} ||
            {_ , _ , _ , Uid , Msg , MsgType , AddTime , FromAvatar , _}
              <- select_limit(qlc:q([X || X <- mnesia:table(tb_uchat_message_record),
              X#tb_uchat_message_record.msgId =:= MsgId]) , Start , Size)],
          if
            FromUserId =:= FromId ->
              #{userid => ToUserId , data => Data};
            true ->
              #{userid => FromUserId , data => Data}
          end
      end , Lists),
    Res
  catch
    _:_ -> #{userid => ToId , data => []}
  end.

do(Q) ->
  F = fun() -> qlc:e(Q) end,
  {atomic, Val} = mnesia:transaction(F),
  Val.

doSort(Q) ->
  F = fun() ->
    qlc:e(qlc:keysort(2 , Q , [{order , descending}]))
      end,
  {atomic , Val} = mnesia:transaction(F),
  Val.

%% 查询分页
select_limit(Q , Start , Size) ->
  try
    if
      Start =:= -1 -> %% 查询分页Top
        F = fun() ->
          QS = qlc:e(qlc:keysort(2 , Q , [{order , descending}])),
          QC = qlc:cursor(QS),
          qlc:next_answers(QC , Size)
            end,
        {atomic , Val} = mnesia:transaction(F),
        lists:reverse(Val);
      true ->
        F = fun() ->
          QS = qlc:e(qlc:keysort(2 , Q , [{order , descending}])),
          QC = qlc:cursor(QS),
          qlc:next_answers(QC , Start),
          qlc:next_answers(QC , Size)
            end,
        {atomic , Val} = mnesia:transaction(F),
        lists:reverse(Val)
    end
  catch
    _:_ -> []
  end.

%%插入消息
add_tb_uchat_message(From , To , Message , MsgType , Time) ->
  Lists = do(qlc:q([X || X <- mnesia:table(tb_uchat_message) ,
    ((X#tb_uchat_message.from =:= From) and (X#tb_uchat_message.to =:= To)) or
      ((X#tb_uchat_message.to =:= From) and (X#tb_uchat_message.from =:= To))])),
  LastMessage = Message,
  if
    length(Lists) =:= 1 ->
      Record = lists:nth(1 , Lists),
      Uuid = Record#tb_uchat_message.msgId,
      Id = Record#tb_uchat_message.id,
      ReFrom = Record#tb_uchat_message.from,
      ReTo = Record#tb_uchat_message.to,
      Row = #tb_uchat_message{id = Id , from = ReFrom , to = ReTo , msgId = Uuid , lastTime = Time , lastMessage = LastMessage , lastMsgType = MsgType},
      F = fun() ->
            mnesia:write(Row)
          end,
      mnesia:transaction(F),
      add_tb_uchat_message_record(From , Message , MsgType , Uuid , Time),
      updateJoinMsg(From , To , Time , MsgType , Message);
    true ->
      Uuid = uuid:uuid_to_string(uuid:get_v4()),
      Id = mnesia:dirty_update_counter(erlang_sequence, tb_uchat_message, 1),
      Row = #tb_uchat_message{id = Id , from = From , to = To , msgId = Uuid , lastTime = Time , lastMessage = LastMessage , lastMsgType = MsgType},
      F = fun() ->
            mnesia:write(Row)
          end,
      mnesia:transaction(F),
      add_tb_uchat_message_record(From , Message , MsgType , Uuid , Time),
      updateJoinMsg(From , To , Time , MsgType , Message)
  end,
  Chats = ets:lookup(session , <<"winchats">>),
  case lists:member(To , Chats) of
    true ->
      ok;
    false ->
      updateMsgUnread(From , To , 9999)
  end.

%% 首次插入消息
add_tb_uchat_msg(From , To , Time) ->
  Lists = do(qlc:q([X || X <- mnesia:table(tb_uchat_message) ,
    ((X#tb_uchat_message.from =:= From) and (X#tb_uchat_message.to =:= To)) or
      ((X#tb_uchat_message.to =:= From) and (X#tb_uchat_message.from =:= To))])),

  if length(Lists) =:= 0 ->
      Uuid = uuid:uuid_to_string(uuid:get_v4()),
      Id = mnesia:dirty_update_counter(erlang_sequence, tb_uchat_message, 1),
      Row = #tb_uchat_message{id = Id , from = From , to = To , msgId = Uuid , lastMsgType = <<"23">> , lastTime = Time},
      F = fun() ->
        mnesia:write(Row)
          end,
      mnesia:transaction(F);
    true ->
      ok
  end.

add_tb_uchat_message_record(UserId , Message , MsgType , MsgId , Time) ->
  #{<<"portrait">> := Portrait} = maps:get(<<"responseBody">> , erlchat_user:userInfo(UserId)),
  Id = mnesia:dirty_update_counter(erlang_sequence, tb_uchat_message_record, 1),
  Row = #tb_uchat_message_record{id = Id , userid = UserId , msg = Message , msgType = MsgType , fromAvatar = Portrait , msgId = MsgId , addTime = Time},
  F = fun() ->
        mnesia:write(Row)
      end,
  mnesia:transaction(F).

query_tb_uchat_message(From , To) ->
  do(qlc:q([X || X <- mnesia:table(tb_uchat_message) ,
    ((X#tb_uchat_message.from =:= From) or (X#tb_uchat_message.to =:= From)) and ((X#tb_uchat_message.to =:= To) or (X#tb_uchat_message.from =:= To))])).

%% 更新未读信息
updateMsgUnread(FromUserId , ToUserId , N) ->
  Lists = do(qlc:q([X || X <- mnesia:table(tb_uchat_message_read) ,
    (X#tb_uchat_message_read.from =:= FromUserId) and (X#tb_uchat_message_read.to =:= ToUserId)])),

  if length(Lists) =:= 1 ->
        Record = lists:nth(1 , Lists),
        Id = Record#tb_uchat_message_read.id,
        Num = erlang:min(Record#tb_uchat_message_read.num , N),
        updateTable(#tb_uchat_message_read{id = Id , from = FromUserId , to = ToUserId , num = Num + 1}),
        updateJoinMsgUnread(FromUserId , ToUserId);
    true ->
        Id = mnesia:dirty_update_counter(erlang_sequence, tb_uchat_message_read, 1),
        updateTable(#tb_uchat_message_read{id = Id , from = FromUserId , to = ToUserId , num = 0}),
        updateJoinMsgUnread(FromUserId , ToUserId)
  end.

totalUnread(UserId) ->
  Lists = do(qlc:q([X || X <- mnesia:table(tb_uchat_message_read) ,
    (X#tb_uchat_message_read.to =:= UserId)])),
  sum(Lists).

sum([H|T]) -> (H#tb_uchat_message_read.num + sum(T));
sum([]) -> 0.

updateJoinMsgUnread(FromUserId , ToUserId) ->
  Lists = do(qlc:q([X || X <- mnesia:table(tb_uchat_join_message) ,
  (X#tb_uchat_join_message.fromUserId =:= FromUserId) and (X#tb_uchat_join_message.toUserId =:= ToUserId)])),
  if
    length(Lists) > 0 ->
      lists:map(fun(Item) ->
        UnRead = unReadMsgNum(ToUserId , FromUserId , ToUserId),
        Row = Item#tb_uchat_join_message{unread = UnRead},
        updateTable(Row)
      end , Lists);
    true ->
      acceptFriendApply(FromUserId , ToUserId)
  end.

updateJoinMsg(FromUserId , ToUserId , LastTime , LastMsgType , LastMessage) ->
  Lists = do(qlc:q([X || X <- mnesia:table(tb_uchat_join_message) ,
    ((X#tb_uchat_join_message.fromUserId =:= FromUserId) and (X#tb_uchat_join_message.toUserId =:= ToUserId)) or
      ((X#tb_uchat_join_message.fromUserId =:= ToUserId) and (X#tb_uchat_join_message.toUserId =:= FromUserId))])),
  if
    length(Lists) > 0 ->
      lists:map(fun(Item) ->
        Row = Item#tb_uchat_join_message{lastTime = LastTime , lastMsgType = LastMsgType , lastMessage = LastMessage},
        updateTable(Row)
      end , Lists);
    true ->
      acceptFriendApply(FromUserId , ToUserId),
      updateMsgUnread(FromUserId , ToUserId , 9999)
end.

unReadMsgNum(UserId , FromUserId , ToUserId) ->
  if UserId =:= FromUserId ->
    Lists = do(qlc:q([X || X <- mnesia:table(tb_uchat_message_read) ,
      ((X#tb_uchat_message_read.from =:= ToUserId) and (X#tb_uchat_message_read.to =:= UserId))])),
    if length(Lists) > 0 ->
       sum(Lists);
       true -> 0
    end;
  true ->
    Lists = do(qlc:q([X || X <- mnesia:table(tb_uchat_message_read) ,
      ((X#tb_uchat_message_read.from =:= FromUserId) and (X#tb_uchat_message_read.to =:= UserId))])),
    if length(Lists) > 0 ->
       sum(Lists);
       true -> 0
    end
  end.

%% 更新表
updateTable(Map) ->
  F = fun()->
        mnesia:write(Map)
      end,
  mnesia:transaction(F).

%%返回会员头像路径
avatarCheck(UserId , Path) ->
  try
    AvatarUrl = list_to_binary("http://39.104.48.81:8088/shop_file/poster/avatar/" ++ binary_to_list(UserId) ++ ".png"),
    if
      AvatarUrl =:= Path -> Path;
      true -> AvatarUrl
    end
  catch
      _:_  -> ""
  end.

server_url() ->
  "https://www.kaidianapp.com/shop_api".

while(Fun , Start) ->
  S = Fun(Start),
  if
    S =:= true ->
      while(Fun , Start + 100);
    true ->
      ok
  end.

%%同步信息
syncJoinInfo() ->
  mnesia:delete_table(tb_uchat_join_message),
  mnesia:create_table(tb_uchat_join_message , [{disc_only_copies, [node()]} , {index , [fromUserId , toUserId , tid]} , {attributes , record_info(fields , tb_uchat_join_message)}]),
  Fun = fun (Start) ->
    Res = httpc:request(erlchat_data:server_url() ++ "/setting/syncUserFriendInfo?start=" ++ integer_to_list(Start) ++ "&userid=0"),
    case Res of
      {ok , {_,_,ResBody}}->
          #{<<"responseBody">> := Lists} = jsx:decode(list_to_binary(ResBody) , [return_maps]),
          if length(Lists) > 0 ->
            lists:map(fun(Item) ->
              Id = mnesia:dirty_update_counter(erlang_sequence, tb_uchat_join_message , 1),
              #{<<"id">> := Tid , <<"fromUserId">> := FromUserId , <<"fromName">> := FromName, <<"fromAvatar">> := FromAvatar ,  <<"fromCompany">> := FromCompany , <<"fromPosition">> := FromPosition,
                <<"toUserId">> := ToUserId ,  <<"toName">> := ToName , <<"toAvatar">> := ToAvatar , <<"toCompany">> := ToCompany , <<"toPosition">> := ToPosition} = Item,
              Messages = do(qlc:q([[X#tb_uchat_message.lastTime , X#tb_uchat_message.lastMsgType , X#tb_uchat_message.lastMessage] || X <- mnesia:table(tb_uchat_message),
                ((X#tb_uchat_message.from =:= FromUserId) and (X#tb_uchat_message.to =:= ToUserId)) or ((X#tb_uchat_message.to =:= FromUserId) and (X#tb_uchat_message.from =:= ToUserId))])),
              UnRead = unReadMsgNum(ToUserId , FromUserId , ToUserId),

              if
                length(Messages) =:= 1 ->
                  [[LastTime , LastMsgType , LastMessage]] = Messages,
                  Row = #tb_uchat_join_message{id = Id , fromUserId = FromUserId , fromName = FromName , fromAvatar = FromAvatar , fromCompany = FromCompany ,
                      fromPosition = FromPosition , toUserId = ToUserId , toName = ToName , toAvatar = ToAvatar , toCompany = ToCompany , toPosition = ToPosition ,
                      lastTime = LastTime , lastMsgType = LastMsgType , lastMessage = LastMessage , unread = UnRead , tid = Tid},
                  F = fun() ->
                        mnesia:write(Row)
                      end,
                  mnesia:transaction(F);
                true -> ok
              end
            end, Lists),
            true;
          true ->
            flase
        end;
      {error , _} ->
        false
    end
  end,

  while(Fun , 0).

%%同步此用户好友信息
acceptFriendApply(UserId , FriendId) ->
  Res = httpc:request(erlchat_data:server_url() ++ "/setting/syncUserFriendInfo?userid=" ++ binary_to_list(UserId) ++ "&friendid=" ++ binary_to_list(FriendId)),
  case Res of
    {ok , {_,_,ResBody}}->
      #{<<"responseBody">> := Lists} = jsx:decode(list_to_binary(ResBody) , [return_maps]),
      if length(Lists) > 0 ->
          lists:map(fun(Item) ->
            Id = mnesia:dirty_update_counter(erlang_sequence, tb_uchat_join_message , 1),
            #{<<"id">> := Tid , <<"fromUserId">> := FromUserId , <<"fromName">> := FromName, <<"fromAvatar">> := FromAvatar ,  <<"fromCompany">> := FromCompany , <<"fromPosition">> := FromPosition,
              <<"toUserId">> := ToUserId ,  <<"toName">> := ToName , <<"toAvatar">> := ToAvatar , <<"toCompany">> := ToCompany , <<"toPosition">> := ToPosition} = Item,
            Messages = do(qlc:q([[X#tb_uchat_message.lastTime , X#tb_uchat_message.lastMsgType , X#tb_uchat_message.lastMessage] || X <- mnesia:table(tb_uchat_message),
              ((X#tb_uchat_message.from =:= FromUserId) and (X#tb_uchat_message.to =:= ToUserId)) or ((X#tb_uchat_message.to =:= FromUserId) and (X#tb_uchat_message.from =:= ToUserId))])),
            UnRead = unReadMsgNum(ToUserId , FromUserId , ToUserId),

            if
              length(Messages) =:= 1 ->
                [[LastTime , LastMsgType , LastMessage]] = Messages,
                Row = #tb_uchat_join_message{id = Id , fromUserId = FromUserId , fromName = FromName , fromAvatar = FromAvatar , fromCompany = FromCompany ,
                  fromPosition = FromPosition , toUserId = ToUserId , toName = ToName , toAvatar = ToAvatar , toCompany = ToCompany , toPosition = ToPosition ,
                  lastTime = LastTime , lastMsgType = LastMsgType , lastMessage = LastMessage , unread = UnRead , tid = Tid},
                F = fun() ->
                  mnesia:write(Row)
                    end,
                mnesia:transaction(F);
              true -> ok
            end
          end, Lists),
          true;
        true ->
          flase
      end;
    {error , _} ->
      false
  end.

updateHistoryInfo()->
  Lists = do(qlc:q([X || X <- mnesia:table(tb_uchat_message)])),
  lists:map(fun(Item) ->
    MsgId = Item#tb_uchat_message.msgId,
    Val = select_limit(qlc:q([Y || Y <- mnesia:table(tb_uchat_message_record) , Y#tb_uchat_message_record.msgId =:= MsgId]) , -1 , 1),
    if length(Val) > 0 ->
          [M|_] = Val,
          updateTable(Item#tb_uchat_message{lastMsgType = M#tb_uchat_message_record.msgType , lastMessage = M#tb_uchat_message_record.msg , lastTime = M#tb_uchat_message_record.addTime}),
          ok;
       true -> no
    end
   end , Lists).

%% 创建表
createTable() ->
  mnesia:delete_table(tb_uchat_message),
  mnesia:delete_table(tb_uchat_message_record),
  mnesia:delete_table(tb_uchat_message_read),
  mnesia:create_table(erlang_sequence, [{attributes, record_info(fields,
    erlang_sequence)} , {type,set}, {disc_copies, [node()]}]),
  mnesia:create_table(tb_uchat_message , [{disc_only_copies, [node()]} , {attributes , record_info(fields , tb_uchat_message)}]),
  mnesia:create_table(tb_uchat_message_record , [{disc_only_copies, [node()]} , {attributes , record_info(fields , tb_uchat_message_record)}]),
  mnesia:create_table(tb_uchat_message_read , [{disc_only_copies, [node()]} , {attributes , record_info(fields , tb_uchat_message_read)}]).