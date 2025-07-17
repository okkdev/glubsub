import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleeunit

import glubsub

pub fn main() {
  gleeunit.main()
}

pub type Message {
  Hello(String)
  Hi(String)
  Shutdown
}

pub fn glubsub_subscribe_test() {
  let assert Ok(topic) = glubsub.new_topic()

  let actor1 = start_actor()
  let actor2 = start_actor()

  let assert Ok(_) = glubsub.subscribe(topic, actor1)
  let assert Error(_) = glubsub.subscribe(topic, actor1)

  let assert Ok(_) = glubsub.subscribe(topic, actor2)

  let subs1 = glubsub.get_subscribers(topic)

  assert list.length(subs1) == 2

  let assert Ok(_) = list.find(subs1, fn(sub) { sub.client == actor1 })

  let assert Ok(_) = list.find(subs1, fn(sub) { sub.client == actor2 })

  let assert Ok(_) = glubsub.unsubscribe(topic, actor2)

  let assert Error(_) = glubsub.unsubscribe(topic, actor2)

  let subs2 = glubsub.get_subscribers(topic)

  assert list.length(subs2) == 1

  let assert Ok(_) = list.find(subs2, fn(sub) { sub.client == actor1 })

  let assert Error(_) = list.find(subs2, fn(sub) { sub.client == actor2 })
}

pub fn glubsub_cleanup_test() {
  let assert Ok(topic) = glubsub.new_topic()

  let actor1 = start_actor()
  let actor2 = start_actor()

  let assert Ok(_) = glubsub.subscribe(topic, actor1)
  let assert Error(_) = glubsub.subscribe(topic, actor1)

  let assert Ok(_) = glubsub.subscribe(topic, actor2)

  let subs1 = glubsub.get_subscribers(topic)

  assert list.length(subs1) == 2

  let assert Ok(_) = list.find(subs1, fn(sub) { sub.client == actor1 })

  let assert Ok(_) = list.find(subs1, fn(sub) { sub.client == actor2 })

  actor.send(actor2, Shutdown)
  process.sleep(100)

  let subs2 = glubsub.get_subscribers(topic)

  assert list.length(subs2) == 1

  let assert Ok(_) = list.find(subs2, fn(sub) { sub.client == actor1 })

  let assert Error(_) = list.find(subs2, fn(sub) { sub.client == actor2 })
}

pub fn glubsub_broadcast_test() {
  let assert Ok(topic) = glubsub.new_topic()

  let actor1 = start_actor()
  let actor2 = start_actor()

  let assert Ok(_) = glubsub.subscribe(topic, actor1)
  let assert Error(_) = glubsub.subscribe(topic, actor1)

  let assert Ok(_) = glubsub.subscribe(topic, actor2)

  let assert Ok(_) = glubsub.broadcast(topic, Hello("Louis"))

  let assert Ok(_) = glubsub.broadcast(topic, Hi("You"))

  process.sleep(200)
}

pub fn glubsub_destroy_test() {
  let assert Ok(topic) = glubsub.new_topic()
  let glubsub.Topic(s) = topic

  let assert Ok(pid) = process.subject_owner(s)
  assert process.is_alive(pid)

  assert glubsub.destroy_topic(topic) == Nil

  // Prevent timing issues with waiting for process death
  process.sleep(500)

  let assert Ok(pid) = process.subject_owner(s)
  assert !process.is_alive(pid)
}

fn handle_message(state: Nil, message: Message) -> actor.Next(Nil, a) {
  case message {
    Hello(x) -> {
      assert x == "Louis"
      actor.continue(state)
    }

    Hi(x) -> {
      assert x == "You"
      actor.continue(state)
    }
    Shutdown -> actor.stop()
  }
}

fn start_actor() {
  let assert Ok(actor.Started(data:, ..)) =
    actor.new(Nil) |> actor.on_message(handle_message) |> actor.start()
  data
}
