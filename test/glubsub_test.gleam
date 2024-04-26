import gleam/erlang/process
import gleam/io
import gleam/otp/actor
import gleeunit
import gleeunit/should

import glubsub

pub fn main() {
  gleeunit.main()
}

type Message {
  Hello(String)
}

pub fn subscribe_test() {
  let assert Ok(topic) = glubsub.new()

  let assert Ok(actor) = actor.start(Nil, handle_message)

  glubsub.subscribe(topic, actor)
  |> should.be_ok

  glubsub.broadcast(topic, Hello("Louis"))
  |> should.be_ok

  glubsub.broadcast(topic, Hello("You"))
  |> should.be_ok

  process.sleep(200)
}

fn handle_message(message: Message, _state) -> actor.Next(a, Nil) {
  case message {
    Hello(x) -> io.debug(x)
  }
  actor.continue(Nil)
}
