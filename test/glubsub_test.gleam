import gleam/erlang/process
import gleam/otp/actor
import gleam/set
import gleeunit
import gleeunit/should

import glubsub

pub fn main() {
  gleeunit.main()
}

type Message {
  Hello(String)
  Hi(String)
}

pub fn glubsub_test() {
  let assert Ok(topic) = glubsub.new()

  let assert Ok(actor1) = actor.start(Nil, handle_message)
  let assert Ok(actor2) = actor.start(Nil, handle_message)

  glubsub.subscribe(topic, actor1)
  |> should.be_ok
  glubsub.subscribe(topic, actor1)
  |> should.be_error

  glubsub.subscribe(topic, actor2)
  |> should.be_ok

  glubsub.broadcast(topic, Hello("Louis"))
  |> should.be_ok

  glubsub.broadcast(topic, Hi("You"))
  |> should.be_ok

  let subs1 = glubsub.get_subscribers(topic)

  subs1
  |> set.size
  |> should.equal(2)

  subs1
  |> set.contains(actor1)
  |> should.be_true

  subs1
  |> set.contains(actor2)
  |> should.be_true

  glubsub.unsubscribe(topic, actor2)
  |> should.be_ok

  glubsub.unsubscribe(topic, actor2)
  |> should.be_error

  let subs2 = glubsub.get_subscribers(topic)

  subs2
  |> set.size
  |> should.equal(1)

  subs2
  |> set.contains(actor1)
  |> should.be_true

  subs2
  |> set.contains(actor2)
  |> should.be_false

  process.sleep(200)
}

fn handle_message(message: Message, state) -> actor.Next(a, Nil) {
  case message {
    Hello(x) ->
      x
      |> should.equal("Louis")
    Hi(x) ->
      x
      |> should.equal("You")
  }
  actor.continue(state)
}
