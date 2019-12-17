-module(erlchat_handler).

-export([init/2]).
-export([websocket_init/1]).
-export([websocket_handle/2]).
-export([websocket_info/2]).
-export([terminate/3]).


init(Req=#{pid := Pid} , Opts) ->
  %% 保存用户会话
  UserId = proplists:get_value(<<"userid">> , cowboy_req:parse_qs(Req)),

  %%用户连接
  io:format("open ====================> websocket [~p]~n" , [UserId]),

  ets:insert(session , {UserId , Pid}),
  ets:insert(session , {Pid , UserId}),
  {cowboy_websocket, Req, Opts , #{
    idle_timeout => 24 * 60 * 60 * 1000}}.

websocket_init(State) ->
  UserId = proplists:get_value(self() , ets:lookup(session , self())),
  MsgData = jsx:encode(#{msgType => <<"100">> , record => erlchat_data:queryMsg(UserId , 6)}),
  erlang:start_timer(1 , self() , MsgData),
  TotalUnread = erlchat_data:totalUnread(UserId),
  Res = #{msgType => <<"97">> , userid => UserId , unread => -99 , totalUnread => TotalUnread},
  ResMsg = jsx:encode(Res),
  erlang:start_timer(1 , self() , ResMsg),
  %%创建进程发送历史申请记录
  MsgPid = spawn(fun erlchat_msg:loop/0),
  MsgPid ! {applyMsg , self() ,  UserId},
  {[], State}.

websocket_handle({text, Msg}, State) ->
  case jsx:is_json(Msg) of
    true ->
      #{<<"msgType">> := MsgType} = jsx:decode(Msg , [return_maps]),

      %%发送文字和图片
      if (MsgType =:= <<"0">>) or (MsgType =:= <<"1">>) ->
          #{<<"fromUserId">> := FromUserId , <<"toUserId">> := ToUserId , <<"message">> := Message} = jsx:decode(Msg , [return_maps]),
          sendMessage(ToUserId , FromUserId , Message , MsgType , State);
      %%发送名片
      (MsgType =:= <<"10">>) ->
          #{<<"fromUserId">> := FromUserId , <<"toUserId">> := ToUserId , <<"message">> := Message} = jsx:decode(Msg , [return_maps]),
          sendCard(ToUserId , FromUserId , Message , State);
      %%接受好友请求
      (MsgType =:= <<"20">>) ->
          #{<<"fromUserId">> := FromUserId , <<"toUserId">> := ToUserId , <<"id">> := Id} = jsx:decode(Msg , [return_maps]),
          accept(ToUserId , FromUserId , Id , State);
      %%拒绝好友请求
      (MsgType =:= <<"21">>) ->
          #{<<"fromUserId">> := FromUserId , <<"toUserId">> := ToUserId , <<"id">> := Id} = jsx:decode(Msg , [return_maps]),
          reject(ToUserId , FromUserId , Id , State);
      %%查询Start开始Size条的历史消息
      (MsgType =:= <<"30">>) ->
          #{<<"fromUserId">> := FromUserId , <<"toUserId">> := ToUserId , <<"start">> := Start , <<"size">> := Size} = jsx:decode(Msg , [return_maps]),
          selectMessage(ToUserId , FromUserId , Start , Size , State);
      %%聊天对话框打开
      (MsgType =:= <<"98">>) ->
          #{<<"fromUserId">> := FromUserId , <<"toUserId">> := ToUserId} = jsx:decode(Msg , [return_maps]),
          openDialog(ToUserId , FromUserId , State);
      %%聊天对话框关闭
      (MsgType =:= <<"99">>) ->
          #{<<"fromUserId">> := FromUserId , <<"toUserId">> := ToUserId} = jsx:decode(Msg , [return_maps]),
          closeDialog(ToUserId , FromUserId , State);
      true ->
          {[], State}
      end;
    false ->
      {[], State}
  end;
websocket_handle(_Data, State) ->
  {[], State}.

websocket_info({timeout, _Ref, Msg}, State) ->
  %%erlang:start_timer(1000 , self() , <<"How' you doin'?">>),
  {[{text, Msg}], State};
websocket_info(_Info, State) ->
  {[], State}.

%%断开连接
terminate(_Reason, _Req, _State) ->
  case ets:member(session , self()) of
    true ->
      UserId = proplists:get_value(self() , ets:lookup(session , self())),
      ets:delete(session , self()),
      ets:delete(session , UserId),
      deleteChatUser(UserId),

      %%连接关闭
      io:format("close ====================> websocket [~p]~n" , [UserId]);
    false ->
      ok
  end,
  ok.

%%发送名片
sendCard(ToUserId , FromUserId , Message , State) ->
  #{<<"msgCode">> := MsgCode , <<"responseBody">> := ResponseBody} = erlchat_user:sendCard(FromUserId , ToUserId , Message),
  case MsgCode of
    <<"0">> ->
      Pid = proplists:get_value(ToUserId , ets:lookup(session , ToUserId)),
      ResMsg = jsx:encode(#{userInfo => ResponseBody , msgType => <<"11">>}),

      %%向此用户发送消息
      erlang:start_timer(1 , Pid , ResMsg),

      erlchat_data:updateMsgUnread(FromUserId , ToUserId , -1),
      erlchat_data:updateMsgUnread(FromUserId , ToUserId , 9999),
      TotalUnread = erlchat_data:totalUnread(ToUserId),
      Res = #{msgType => <<"97">> , userid => ToUserId , unread => -99 , totalUnread => TotalUnread},
      erlang:start_timer(1 , Pid , jsx:encode(Res)),
      Time = erlchat_date:localNowSeconds(),
      erlchat_data:add_tb_uchat_msg(FromUserId , ToUserId , Time);
    _ ->
      ok
  end,
  {[], State}.

%% 查询以Start 开始 Size结束的历史消息
selectMessage(ToUserId , FromUserId , Start , Size , State) ->
  MsgData = jsx:encode(#{msgType => <<"31">> , record => erlchat_data:queryMsgSelect(ToUserId , FromUserId , Start , Size)}),
  {[{text , MsgData}], State}.

%% 发送消息
sendMessage(ToUserId , FromUserId , Message , MsgType , State) ->
  Pid = proplists:get_value(ToUserId , ets:lookup(session , ToUserId)),
  FromUserInfo = maps:get(<<"responseBody">> , erlchat_user:userInfo(FromUserId)),
  ToUserInfo = maps:get(<<"responseBody">> , erlchat_user:userInfo(ToUserId)),
  Time = erlchat_date:localNowSeconds(),
  #{<<"portrait">> := FromAvatar} = FromUserInfo,
  ToSendMessageMap = #{userid => FromUserId , touserid => ToUserId,  message => Message ,
    msgType => MsgType , fromAvatar => FromAvatar , fromUserInfo => FromUserInfo , toUserInfo => ToUserInfo , lastTime => Time},
  FromSendMessageMap = #{userid => FromUserId , touserid => ToUserId, message => Message , msgType => MsgType ,
    fromAvatar => FromAvatar, fromUserInfo => FromUserInfo , toUserInfo => ToUserInfo , lastTime => Time},
  ToSendMsg = jsx:encode(ToSendMessageMap),
  FromSendMsg = jsx:encode(FromSendMessageMap),

  %%创建进程写入数据库
  MsgPid = spawn(fun erlchat_msg:loop/0),
  MsgPid ! {addMsg , Pid ,  FromUserId , ToUserId , Message , MsgType , Time},

  case Pid =/= undefined of
    true ->

      %%判断是否发送给自己
      if FromUserId =/= ToUserId ->
        erlang:start_timer(1 , Pid , ToSendMsg);
        true ->
          true
      end,
      {[{text , FromSendMsg}], State};
    false ->
      {[{text , FromSendMsg}], State}
  end.

%%接受好友请求
accept(ToUserId , FromUserId , Id , State) ->
  #{<<"msgCode">> := MsgCode} = erlchat_user:accept(Id , FromUserId),
  case MsgCode of
    <<"0">> ->
      Pid = proplists:get_value(ToUserId , ets:lookup(session , ToUserId)),
      FromPid = proplists:get_value(FromUserId , ets:lookup(session , FromUserId)),
      FromUserInfo = maps:get(<<"responseBody">> , erlchat_user:userInfo(FromUserId)),
      ToUserInfo = maps:get(<<"responseBody">> , erlchat_user:userInfo(ToUserId)),
      Time = erlchat_date:localNowSeconds(),
      erlchat_data:updateMsgUnread(FromUserId , ToUserId , -1),
      erlchat_data:updateMsgUnread(FromUserId , ToUserId , 9999),
      TotalUnread = erlchat_data:totalUnread(ToUserId),
      UnRead = erlchat_data:unReadMsgNum(ToUserId , FromUserId , ToUserId),

      ToResMsg = jsx:encode(#{status => 0 , userid => FromUserId , message => "对方已接受你的请求" , msgType => <<"23">> ,
        userInfo => FromUserInfo , unread => UnRead , lastTime => Time}),

      erlchat_data:updateMsgUnread(ToUserId , FromUserId , -1),
      erlchat_data:updateMsgUnread(ToUserId , FromUserId , 9999),
      FromTotalUnread = erlchat_data:totalUnread(FromUserId),
      FromUnRead = erlchat_data:unReadMsgNum(FromUserId , ToUserId , FromUserId),
      FromResMsg = jsx:encode(#{status => 0 , userid => ToUserId ,  message => "对方已接受你的请求" , msgType => <<"23">> ,
        userInfo => ToUserInfo , unread => FromUnRead , lastTime => Time}),

      ToResRead = #{msgType => <<"97">> , userid => FromUserId , unread => UnRead , totalUnread => TotalUnread},
      FromResRead = #{msgType => <<"97">> , userid => ToUserId , unread => FromUnRead , totalUnread => FromTotalUnread},

      %%向此用户发送消息
      erlang:start_timer(1 , Pid , ToResMsg),
      erlang:start_timer(1 , Pid , jsx:encode(ToResRead)),

      erlang:start_timer(1 , FromPid , FromResMsg),
      erlang:start_timer(1 , FromPid , jsx:encode(FromResRead));
    _ ->
      ok
  end,
  {[], State}.

%%拒绝好友请求
reject(ToUserId , FromUserId , Id , State) ->
  #{<<"msgCode">> := MsgCode} = erlchat_user:reject(Id , FromUserId),
  case MsgCode of
    <<"0">> ->
      Pid = proplists:get_value(ToUserId , ets:lookup(session , ToUserId)),
      FromUserInfo = maps:get(<<"responseBody">> , erlchat_user:userInfo(FromUserId)),
      ToUserInfo = maps:get(<<"responseBody">> , erlchat_user:userInfo(ToUserId)),
      Time = erlchat_date:localNowSeconds(),
      ResMsg = jsx:encode(#{status => 1 , message => "对方已拒绝你的请求" , msgType => <<"23">> ,
        fromUserInfo => FromUserInfo , toUserInfo => ToUserInfo , lastTime => Time}),
      %%向此用户发送消息
      erlang:start_timer(1 , Pid , ResMsg);
    _ ->
      ok
  end,
  {[], State}.

%%打开对话框
openDialog(ToUserId , FromUserId , State) ->

  %%添加用户
  addChatUser(FromUserId),
  erlchat_data:updateMsgUnread(ToUserId , FromUserId , -1),
  TotalUnread = erlchat_data:totalUnread(FromUserId),
  Res = #{msgType => <<"97">> , userid => ToUserId , unread => 0 , totalUnread => TotalUnread},
  ResMsg = jsx:encode(Res),
  {[{text , ResMsg}] , State}.

%%关闭对话框
closeDialog(_ , FromUserId , State) ->
  deleteChatUser(FromUserId),
  {[], State}.

%%删除用户
deleteChatUser(UserId) ->
  Chats = getChats(),
  ChatsArr = lists:delete(UserId , Chats),
  ets:insert(session , {<<"winchats">> , ChatsArr}).

%%添加用户
addChatUser(UserId) ->
  Chats = lists:delete(UserId , getChats()),
  ChatsArr = lists:append(Chats , [UserId]),
  ets:insert(session , {<<"winchats">> , ChatsArr}).

%%获取用户
getChats() ->
  try
    ets:lookup(session , <<"winchats">>)
  catch
    _:_  -> []
  end.
