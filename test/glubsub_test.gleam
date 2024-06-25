import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleeunit
import gleeunit/should

import glubsub

pub fn main() {
  gleeunit.main()
}

type Message {
  Hello(String)
  Hi(String)
  Shutdown
}

pub fn glubsub_subscribe_test() {
  let assert Ok(topic) = glubsub.new_topic()

  let assert Ok(actor1) = actor.start(Nil, handle_message)
  let assert Ok(actor2) = actor.start(Nil, handle_message)

  glubsub.subscribe(topic, actor1)
  |> should.be_ok
  glubsub.subscribe(topic, actor1)
  |> should.be_error

  glubsub.subscribe(topic, actor2)
  |> should.be_ok

  let subs1 = glubsub.get_subscribers(topic)

  subs1
  |> list.length
  |> should.equal(2)

  subs1
  |> list.find(fn(sub) { sub.client == actor1 })
  |> should.be_ok

  subs1
  |> list.find(fn(sub) { sub.client == actor2 })
  |> should.be_ok

  glubsub.unsubscribe(topic, actor2)
  |> should.be_ok

  glubsub.unsubscribe(topic, actor2)
  |> should.be_error

  let subs2 = glubsub.get_subscribers(topic)

  subs2
  |> list.length
  |> should.equal(1)

  subs2
  |> list.find(fn(sub) { sub.client == actor1 })
  |> should.be_ok

  subs2
  |> list.find(fn(sub) { sub.client == actor2 })
  |> should.be_error
}

pub fn glubsub_cleanup_test() {
  let assert Ok(topic) = glubsub.new_topic()

  let assert Ok(actor1) = actor.start(Nil, handle_message)
  let assert Ok(actor2) = actor.start(Nil, handle_message)

  glubsub.subscribe(topic, actor1)
  |> should.be_ok
  glubsub.subscribe(topic, actor1)
  |> should.be_error

  glubsub.subscribe(topic, actor2)
  |> should.be_ok

  let subs1 = glubsub.get_subscribers(topic)

  subs1
  |> list.length
  |> should.equal(2)

  subs1
  |> list.find(fn(sub) { sub.client == actor1 })
  |> should.be_ok

  subs1
  |> list.find(fn(sub) { sub.client == actor2 })
  |> should.be_ok

  actor.send(actor2, Shutdown)
  process.sleep(100)

  let subs2 = glubsub.get_subscribers(topic)

  subs2
  |> list.length
  |> should.equal(1)

  subs2
  |> list.find(fn(sub) { sub.client == actor1 })
  |> should.be_ok

  subs2
  |> list.find(fn(sub) { sub.client == actor2 })
  |> should.be_error
}

pub fn glubsub_broadcast_test() {
  let assert Ok(topic) = glubsub.new_topic()

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

  process.sleep(200)
}

pub fn glubsub_destroy_test() {
  let assert Ok(topic) = glubsub.new_topic()
  let glubsub.Topic(s) = topic

  process.is_alive(process.subject_owner(s))
  |> should.be_true

  glubsub.destroy_topic(topic)
  |> should.equal(Nil)

  process.is_alive(process.subject_owner(s))
  |> should.be_false
}

fn handle_message(message: Message, state) -> actor.Next(a, Nil) {
  case message {
    Hello(x) -> {
      x
      |> should.equal("Louis")
      actor.continue(state)
    }

    Hi(x) -> {
      x
      |> should.equal("You")
      actor.continue(state)
    }
    Shutdown -> actor.Stop(process.Normal)
  }
}
