import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/set.{type Set}

pub type Message(m) {
  Subscribe(client: Subject(m))
  Unsubscribe(client: Subject(m))
  Broadcast(message: m)
}

pub fn new() -> Result(Subject(Message(m)), actor.StartError) {
  actor.start(set.new(), handle_message)
}

pub fn subscribe(
  topic: Subject(Message(m)),
  client: Subject(m),
) -> Result(Nil, Nil) {
  actor.send(topic, Subscribe(client))
  |> Ok
}

pub fn broadcast(topic: Subject(Message(m)), message: m) -> Result(Nil, Nil) {
  actor.send(topic, Broadcast(message))
  |> Ok
}

fn handle_message(
  message: Message(m),
  state: Set(Subject(m)),
) -> actor.Next(a, Set(Subject(m))) {
  case message {
    Subscribe(client) -> actor.continue(set.insert(state, client))
    Unsubscribe(client) -> actor.continue(set.delete(state, client))
    Broadcast(message) -> {
      set.to_list(state)
      |> list.each(fn(subscriber) { actor.send(subscriber, message) })
      actor.continue(state)
    }
  }
}
