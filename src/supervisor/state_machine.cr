module Supervisor

  enum State
    STOPPED
    FATAL
    EXITED
    STARTING
    BACKOFF
    RUNNING
    STOPPING

    def stopped?
      [STOPPED, FATAL].includes? self
    end

    def started?
      [STARTING, BACKOFF, RUNNING].includes? self
    end

    def running?
      self == RUNNING
    end
  end

  enum Event
    START
    STOP
    STARTED
    EXITED
    RETRY
    FATAL
  end

  alias EventCallback = Proc(State, State, Nil)

  class StateMachine

    include Logger

    getter state = State::STOPPED
    getter start_proc : Proc(Void)
    getter stop_proc : Proc(Void)

    @try_count = 0
    @chan = Channel(Event).new
    @retries : Int32
    @autorestart : Bool
    @state_stream : StateStream

    def initialize(@retries, @start_proc, @stop_proc, @autorestart, @state_stream)
      listen
    end

    def fire(event : Supervisor::Event, async = false)
      if async
        @chan.send(event)
      else
        spawn { @chan.send(event) }
      end
    end

    private def listen
      spawn do
        loop do
          event = @chan.receive
          process_event event
        end
      end
    end

    private def process_event(event : Event)
      prev_state = @state
      case {state, event}

      when {State::STOPPED, Event::START}
        @state = State::STARTING
        @start_proc.call

      when {State::FATAL, Event::START}
        @state = State::STARTING
        @start_proc.call

      when {State::EXITED, Event::START}
        @state = State::STARTING
        @start_proc.call

      when {State::STARTING, Event::STARTED}
        @state = State::RUNNING
        @try_count = 0

      when {State::STARTING, Event::EXITED}
        @state = State::BACKOFF
        @try_count += 1
        if @try_count >= @retries
          fire Event::FATAL
        else
          fire Event::RETRY
        end

      when {State::STARTING, Event::STOP}
        @state = State::STOPPING
        @stop_proc.call

      when {State::BACKOFF, Event::RETRY}
        @state = State::STARTING
        @start_proc.call

      when {State::BACKOFF, Event::FATAL}
        @state = State::FATAL

      when {State::RUNNING, Event::STOP}
        @state = State::STOPPING
        @stop_proc.call

      when {State::RUNNING, Event::EXITED}
        @state = State::EXITED
        fire Event::START if @autorestart

      when {State::STOPPING, Event::EXITED}
        @state = State::STOPPED
      else
        puts "unknown state/event combo: #{@state}, #{event}"
      end

      @state_stream.publish(prev_state, @state)
    end
  end
end
