
# Meta-learner that can compose sub-managers of optimization components in a type-stable way.
# A sub-manager is any LearningStrategy, and may implement any subset of callbacks.
type MetaLearner{MGRS <: Tuple} <: LearningStrategy
    managers::MGRS
end

function MetaLearner(mgrs::LearningStrategy...)
    MetaLearner(mgrs)
end

pre_hook(meta::MetaLearner,  model)    = foreach(mgr -> pre_hook(mgr, model),      meta.managers)
iter_hook(meta::MetaLearner, model, i) = foreach(mgr -> iter_hook(mgr, model, i),  meta.managers)
finished(meta::MetaLearner,  model, i) = any(mgr     -> finished(mgr, model, i),   meta.managers)
post_hook(meta::MetaLearner, model)    = foreach(mgr -> post_hook(mgr, model),     meta.managers)

# This is the core iteration loop.  Iterate through data, checking for
# early stopping after each iteration.
function learn!(model, meta::MetaLearner, data)
    pre_hook(meta, model)
    for (i, item) in enumerate(data)
        for mgr in meta.managers
            learn!(model, mgr, item)
        end

        iter_hook(meta, model, i)
        finished(meta, model, i) && break
    end
    post_hook(meta, model)
end

# return nothing forever
type InfiniteNothing end
Base.start(itr::InfiniteNothing) = 1
Base.done(itr::InfiniteNothing, i) = false
Base.next(itr::InfiniteNothing, i) = (nothing, i+1)


# we can optionally learn without input data... good for minimizing functions
function learn!(model, meta::MetaLearner)
    learn!(model, meta, InfiniteNothing())
end

# TODO: can we instead use generated functions for each MetaLearner callback so that they are ONLY called for
#   those methods which the manager explicitly implements??  We'd need to have a type-stable way
#   of checking whether that manager implements that method.

# @generated function pre_hook(meta::MetaLearner, model)
#     body = quote end
#     mgr_types = meta.parameters[1]
#     for (i,T) in enumerate(mgr_types)
#         if is_implemented(T, :pre_hook)
#             push!(body.args, :(pre_hook(meta.managers[$i], model)))
#         end
#     end
#     body
# end

# -------------------------------------------------------------

function make_learner(args...; kw...)
    strats = []
    for (k,v) in kw
        if k == :maxiter
            push!(strats, MaxIter(v))
        elseif k == :oniter
            push!(strats, IterFunction(v))
        elseif k == :converged
            push!(strats, ConvergenceFunction(v))
        end
    end
    MetaLearner(args..., strats...)
end

# add to an existing meta
function make_learner(meta::MetaLearner, args...; kw...)
    make_learner(meta.managers..., args...; kw...)
end
