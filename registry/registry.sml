signature REGISTRY =
  sig
    type 'a t
    val init : unit -> 'a t
    val register : 'output t -> 'input Universal.tag * ('input -> 'output) -> unit
    val apply : 'a t -> Universal.universal -> 'a
  end

structure Registry :> REGISTRY =
  struct
    type 'a t = (Universal.universal -> 'a) ref

    fun init () = ref (fn _ => raise Fail "Method not found!")
    fun register registry (tag,f) = Ref.modify (fn g =>
        fn u =>
          if Universal.tagIs tag u
            then f (Universal.tagProject tag u)
            else g u
      ) registry
    val apply = !
  end


val r : string Registry.t = Registry.init ()
val int1 : int Universal.tag = Universal.tag ()
val int2 : int Universal.tag = Universal.tag ()
val int3 : int Universal.tag = Universal.tag ()
val string : string Universal.tag = Universal.tag ()
val () = Registry.register r (int1, Int.toString)
val () = Registry.register r (int2, Fn.const "hello")
val () = Registry.register r (string, Fn.id)

val show = fn (tag,x) => print (
  (
    Registry.apply r (Universal.tagInject tag x)
      handle e => exnMessage e
  ) ^ "\n"
)

val () = show (int1,3)
val () = show (int2,3)
val () = show (int3,3)
val () = show (string,"test")

(* Produces:

3
hello
Fail: Method not found!
test

*)
