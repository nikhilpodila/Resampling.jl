
struct FourCornersVariant <: AbstractPolicy
    high_prob::Float64
    low_prob::Float64
    state_to_weights_map::Dict{Array{Int64, 1}, Weights}
    function FourCornersVariant(high_prob, low_prob)
        map = Dict{Array{Int64, 1}, Weights}(
            [3,2]=>Weights([high_prob, low_prob, low_prob, high_prob]),
            [3,9]=>Weights([high_prob, high_prob, low_prob, low_prob]),
            [10,2]=>Weights([low_prob, low_prob, high_prob, high_prob]),
            [10,9]=>Weights([low_prob, high_prob, high_prob, low_prob])
        )
        new(high_prob, low_prob, map)
    end
end

FourCornersVariant() = FourCornersVariant(0.45, 0.05)

function Base.get(π::FourCornersVariant, state_t, action_t, state_tp1, action_tp1, preds_tp1)
    prob = -1.0
    if state ∈ keys(π.state_to_weights_map)
        prob = π.state_to_weights_map[state][action_t]
    else
        prob = 0.25
    end
    return prob
end

function StatsBase.sample(rng::Random.AbstractRNG, π::FourCornersVariant, state)
    act = -1
    if state ∈ keys(π.state_to_weights_map)
        act = StatsBase.sample(rng, 1:4, π.state_to_weights_map[state])
    else
        act = rand(rng, 1:4)
    end

    return act
end

function find_same(states)
    s=0
    for p in collect(Iterators.product(states,states))
        s += if (p[1] == p[2]) 1 else 0 end
    end
    return (s - length(states))/2
end

function gen_states(seed, num)
    mt = Random.MersenneTwister(seed)
    states = []
    while length(states) < num
        new_state = rand(mt, 1:11, 2)
        if !(new_state in states)
            append!(states, [new_state])
        end
    end
    return states
end

struct RandomStateVariant <: AbstractPolicy
    states::Array{Array{Int64, 1}, 1}
    weights::Weights
end

RandomStateVariant(action, prob, num_states, seed) =
    RandomStateVariant(gen_states(seed, num_states),
                       Weights([
                           act == action ? prob : (1.0-prob)/3
                           for act in 1:4
                       ]))

RandomStateVariant() =
    RandomStateVariant(FourRoomsParams.DOWN, 0.05, 25, 1143139448)

function Base.get(π::RandomStateVariant, state_t::Array{Int64, 1}, action_t, state_tp1, action_tp1, preds_tp1)
    prob = -1.0
    if state_t ∈ π.states
        prob = π.weights[action_t]
    else
        prob = 0.25
    end
    return prob
end

function Base.get(π::RandomStateVariant, state_t::CartesianIndex{2}, action_t, state_tp1, action_tp1, preds_tp1)
    return StatsBase.get(π, [state_t[1], state_t[2]], action_t, state_tp1, action_tp1, preds_tp1)
end

function StatsBase.sample(rng::Random.AbstractRNG, π::RandomStateVariant, state::Array{Int64, 1})
    act = -1
    if state ∈ π.states
        act = StatsBase.sample(rng, 1:4, π.weights)
    else
        act = rand(rng, 1:4)
    end
    return act
end

function StatsBase.sample(rng::Random.AbstractRNG, π::RandomStateVariant, state::CartesianIndex{2})
    return StatsBase.sample(rng, π, [state[1], state[2]])
end


# # Changing behaviour policy
# mutable struct changing_behavior
#     freq
#     step
# end

# function next_action_cp(CB::changing_behavior, state_t; rng=Random.GLOBAL_RNG)

# end

# function probability_cp(CB::changing_behavior, state_t, action_t; rng=Random.GLOBAL_RNG)

# end


# function create_changing_behavior_policy(freq)
#     changing_behavior(freq, 0)

# end
