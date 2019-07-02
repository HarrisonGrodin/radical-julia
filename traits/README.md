# Traits

Multiple inheritance, sans inheritance.

---

## Introduction

What does it mean to have `x::T`? There are two possible cases:
1. `T` is concrete. Then, `x` is (structurally) an inhabitant of `T`. For example, if `T` is defined as a `struct`, `T` has the appropriate fields.
2. `T` is abstract. Then, `x` is an inhabitant of some type `U`, where `U <: T` (directly or not).

Let's look at an example using the `Number` abstract type.
```julia
f(x::Number) = (2x, length(string(abs(x))))
f(x::Int) = (x << 1, x == 0 ? 1 : (floor(Int, log10(abs(x)) + 1)))
```

Here, we define the default functionality for `f(x)` and then provide a specialized version for the `Int` type.
In order to prevent bugs, we annotated the first method with `::Number`, programmatically noting to the user that this method requires something which behaves like a number.

We'll continue with this distinction in mind - given an abstract type `A` and a concrete type `T`, `x::A` if `x::T` and **all instances of `T` behave like an `A`**.

Returning to our example, note the implicit contract `Number` has: if some `T <: Number`, we expect that methods `Base.:*(::T, ::T)` and `Base.abs(::T)` exist, both producing results of type `T`. (Note that other methods are likely required to exist, such as `Base.:+(::T, ::T)`.) However, note the call to `string` - we _also_ assume that `x` can be displayed as a string. Thus, we almost wish to write:
```julia
f(x::T) where {T<:Number, T<:Displayable} = (2x, length(string(abs(x))))
```

This would prevent a user from metaphorically shooting herself in the foot, passing an input to `f` for which a reasonable `string` method is not defined. Fantastic - now, how do we set this up? We'll need either `Displayable <: Number` or `Number <: Displayable` to preserve the subtyping relation. Which do we choose? The first seems clearly wrong; there are lots of types that are numbers but not displayable. At first, the second seems appealing; however, what about situations where numbers aren't easily displayable (e.g. infinite-precision floats, as functions from `Int` to `Bool`)? It seems like these two abstract types, while often overlapping, should be distinct. Enter *multiple inheritance*.


## Multiple Inheritance

There's an easy solution to all of this - multiple inheritance! We allow types to be subtypes of many abstract types:


```julia
abstract type MathExpression end

struct MathSymbol <: MathExpression, Number
    x::Symbol
end
struct MathFunction <: MathExpression, Number
    fn::Symbol
    args::Vector{Number}
end
```
```julia
struct OrderedSet{T} <: AbstractVector{T}, AbstractVector{T}
    # ...
end
```

It's a dream come true, right? Sure - until you get to method ambiguity, where the dream becomes a nightmare.

```julia
abstract type A end
abstract type B end
abstract type C end
f(::A, ::A) = 1
f(::A, ::C) = 2
f(::B, ::B) = 3
f(::B, ::C) = 4
f(::C, ::B) = 5
f(::C, ::C) = 6

struct T <: A, B, C end
struct U <: C, A end
```

Imagine the ambiguities - what do you even do with `f(::T, ::T)`? Encouraging this style has the potential to render any reasonable codebase incomprehensible.


## Zero Inheritance

So, turning the inheritance tree into an inheritance directed-acyclic-graph wasn't the best. Rather than clarifying the interface for functions, we created tons of overlapping methods. Let's try a different approach, starting with grouping together the methods we believe look like an interface.

```julia
module NumberAPI
    function zero end
    function + end
    function - end
    x - y = x + (-y)

    function one end
    function * end
    function inv end
    x / y = x * inv(y)
end

module IndexableAPI
    function eachindex end
    function getindex end

    firstindex(iter) = first(eachindex(iter))
    lastindex(iter)  = last(eachindex(iter))
end
```

Some of the functions seem to have natural implementations in terms of the other functions, such as `/` and `firstindex`, so we decide to include them.

The functions in our `NumberAPI` module should satisfy an important property - they are implemented for some type `T` if and only if `T <: Number`. Wait - doesn't this mean we just get rid of the abstract type `Number` altogether? Let's look at a simpler example using trait-like syntax:

```julia
trait Ordered{T}
    isless(::T, ::T)
    x < y = isless(x, y)
    x > y = isless(y, x)
end

implement Ordered{Int}
    # implicitly:
    # import Ordered: isless, <, >

    isless(x::Int, y::Int) = int_lt(x, y)
end
```

We could now write code like this:
```julia
minmax(x::T, y::T) where Ordered{T} = x < y ? (y, x) : (x, y)
function biggest_two(v::Vector{T}) where Ordered{T}
    length(v) ≥ 2 || error("input too short")
    x, y = minmax(v[1], v[2])
    for z ∈ v[3:end]
        if z > y
            if z > x
                x, y = z, x
            else
                y = z
            end
        end
    end
    return (x, y)
end
```
Before running the `minmax` function on arguments of type `T`, we check that it they're reasonably orderable. Similarly, before running `biggest_two` on a vector containing type `T`, we check that `T` can be ordered.

Can't this get tedious, though? Shouldn't some `implement` statements be automatically generated? Of course - if a type `T` is equatable, `Vector{T}` should be, too:
```julia
trait Eq{T}
    x::T == y::T
    x::T != y::T = !(x == y)
end

implement Eq{Vector{T}} where Eq{T}
    function ==(xs::Vector{T}, ys::Vector{T})
        length(xs) == length(ys) || return false
        for i ∈ eachindex(xs)
            xs[i] == ys[i] || return false
        end
        return true
    end
end
```

Also, it might make sense for some traits to depend on other traits. For example, a type `T` should only be orderable given that it's equatable:
```julia
trait Ordered{T} <: Eq{T}
    isless(::T, ::T)
    x < y = isless(x, y)
    x > y = isless(y, x)
end
```

This would require (or assume) that an implementation of `Eq{T}` is already defined when an instance of `Ordered{T}` is defined, allowing the functions within `Ordered{T}` (and any function which has `where Ordered{T}`) to safely make use of equality checking too.

Look how much power this simple setup gets us! Here are some demonstrations of how some of the already-documented [Julia interfaces](https://docs.julialang.org/en/v1/manual/interfaces/index.html) could be implemented:
```julia
trait Indexable{T}
    getindex(::T, inds...)
    setindex!(::T, v, inds...)
    eachindex(::T)

    firstindex(iter) = first(eachindex(iter))
    lastindex(iter)  = last(eachindex(iter))
end

trait Iterable{T}
    iterate(::T)
    iterate(::T, state)
end

function first(itr::T) where Iterable{T}
    x = iterate(itr)
    x === nothing && throw(ArgumentError("collection must be non-empty"))
    x[1]
end

trait FiniteIterable{T} <: Iterable{T}
    length(::T)
end

trait TypedIterable{T} <: Iterable{T}
    eltype(::T)
end

trait AbstractArray{T} <: Indexable{T}, FiniteIterable{T}
    size(::T)
    function similar end
end
```

Notice how multiple "inheritance" is no longer a burden - we can have trait dependencies with ease. We can even parameterize traits over multiple types:
```julia
trait Convert{T,X}
    convert(::Type{T}, x::X)
end

const IntLike = Convert{Int}
function int_sum(xs::Vector{T}) where IntLike{T}
    sum = 0
    for x ∈ xs
        sum += convert(Int, x)
    end
    return sum
end
```


## Conclusion

By treating the current notion of subtyping differently, we encounter a new way of thinking about traits and function interfaces. There are a number of concrete benefits:

- **Safety.** When designing a function, the developer can concisely and programmatically specify what functions it assumes are defined for the input. Implicit requirements about inputs can be made explicit.
- **Clarity.** Since every value `x` will have exactly one type `T` (with exceptions of unions, etc.), there is little chance for runtime error due to dispatch ambiguity.

The execution of this proposal may encounter a number of challenges. For example:

- How would we deal with type promotions? For instance, how would we specify that `2 + 3.0` should know to to dispatch to `Num{Float64}`?
- Where would one need to specify types to dispatch on, and where could it be inferred? (For example, in an `impl Foo{T}`, could one define `bar(x) = x` instead of `bar(x::T) = x`?)
- How could we, as a community, transition code which doesn't meet the new/official trait interface without excessive tedious work?
