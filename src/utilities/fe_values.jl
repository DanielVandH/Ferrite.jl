type FEValues{dim, T <: Real, FS <: FunctionSpace}
    J::Matrix{T}
    Jinv::Matrix{T}
    N::Vector{Vector{T}}
    dNdx::Vector{Matrix{T}}
    dNdξ::Vector{Matrix{T}}
    detJdV::Vector{T}
    quad_rule::QuadratureRule{dim}
    function_space::FS
end

"""
Initializes an `FEValues` object from a function space and a quadrature rule.
"""
function FEValues{dim, T, FS <: FunctionSpace}(::Type{T}, quad_rule::QuadratureRule{dim}, func_space::FS)
        n_basefuncs = n_basefunctions(func_space)

        n_qpoints = length(points(quad_rule))

        N = [zeros(T, n_basefuncs) for i in 1:n_qpoints]
        dNdx = [zeros(T, dim, n_basefuncs) for i in 1:n_qpoints]
        dNdξ = [zeros(T, dim, n_basefuncs) for i in 1:n_qpoints]
        J = zeros(T, dim, dim)
        Jinv = similar(J)

        for (i, (ξ, w)) in enumerate(zip(quad_rule.points, quad_rule.weights))
            value!(func_space, N[i], ξ)
            derivative!(func_space, dNdξ[i], ξ)
        end

        FEValues{dim, T, FS}(J, Jinv, N, dNdx, dNdξ, zeros(T, n_qpoints), quad_rule, func_space)
end
function FEValues{dim, FS <: FunctionSpace}(quad_rule::QuadratureRule{dim}, func_space::FS)
    FEValues(Float64, quad_rule, func_space)
end

"""
Updates the `FEValues` object for the current element with coordinate matrix `x`.
"""
function reinit!(fe_v::FEValues, x::Matrix)
    for (i, (ξ, w)) in enumerate(zip(fe_v.quad_rule.points, fe_v.quad_rule.weights))
        @into! fe_v.J = fe_v.dNdξ[i] * x'
        inv_spec!(fe_v.Jinv, fe_v.J)
        @into! fe_v.dNdx[i] = fe_v.Jinv * fe_v.dNdξ[i]
        fe_v.detJdV[i] = det_spec(fe_v.J) * w
    end
end

"""
Returns the quadrature rule.
"""
get_quadrule(fe_v::FEValues) = fe_v.quad_rule

"""
Returns the function space.
"""
get_functionspace(fe_v::FEValues) = fe_v.function_space

"""
Gets the product between the determinant of the Jacobian and the quadrature point weight for a given quadrature point.
"""

@inline detJdV(fe_v::FEValues, q_point::Int) = fe_v.detJdV[q_point]

"""
    shape_value(fe_v, q_point::Int) -> value

Gets the value of the shape function for a given quadrature point
"""
@inline shape_value(fe_v::FEValues, q_point::Int) = fe_v.N[q_point]

"""
    shape_value(fe_v, q_point::Int, base_func::Int) -> value

Gets the value of the shape function at a given quadrature point and given base function
"""
@inline shape_value(fe_v::FEValues, q_point::Int, base_func::Int) = fe_v.N[q_point][base_func]

"""
    shape_gradient(fe_v, q_point::Int) -> gradient::Matrix

Get the gradients of the shape functions for a given quadrature point
"""
@inline shape_gradient(fe_v::FEValues, q_point::Int) = fe_v.dNdx[q_point]

"""
    shape_gradient(fe_v, q_point::Int, base_func::Int) -> gradient::Vector

Get the gradient of the shape functions for a given quadrature point and base function
"""
@inline shape_gradient(fe_v::FEValues, q_point::Int, base_func::Int) = fe_v.dNdx[q_point][:, base_func]

"""
    shape_gradient(fe_v, q_point::Int, base_func::Int, component::Int) -> gradient_component

Get the gradient of the shape functions for a given quadrature point, base function and component
"""
@inline shape_gradient(fe_v::FEValues, q_point::Int, base_func::Int, component::Int) = fe_v.dNdx[q_point][component, base_func]

const shape_derivative = shape_gradient

"""
    function_scalar_value(fe_v, q_point::Int, u::Vector) -> value

Computes the value in a quadrature point for a scalar valued function
"""
@inline function function_scalar_value{dim, T}(fe_v::FEValues{dim}, q_point::Int, u::Vector{T})
    @assert length(u) == n_basefunctions(get_functionspace(fe_v))
    N = shape_value(fe_v, q_point)
    return dot(u, N)
end

# u should be given as [x, y, z, x, y, z, ...]
"""
     function_vector_value!(vec::Vector, fe_v, q_point::Int, u::Vector) -> value

Computes the value in a quadrature point for a vector valued function. Result is stored
in `vec`
"""
@inline function function_vector_value!{dim, T}(vec::Vector{T}, fe_v::FEValues{dim}, q_point::Int, u::Vector{T})
    n_base_funcs = n_basefunctions(get_functionspace(fe_v))
    @assert length(u) == dim * n_base_funcs
    @assert length(vec) == dim
    fill!(vec, 0.0)
    N = shape_value(fe_v, q_point)
    for i in 1:n_base_funcs
        offset = dim*(i-1)
        for j in 1:dim
            vec[j] += N[i] * u[offset + j]
        end
    end
    return vec
end

"""
    function_scalar_gradient!(grad::Vector, fe_v, q_point::Int, u::Vector) -> gradient

Computes the gradient in a quadrature point for a scalar valued function. Result
is stored in `grad`.
"""
@inline function function_scalar_gradient!{dim, T}(grad::Vector{T}, fe_v::FEValues{dim}, q_point::Int, u::Vector{T})
    n_base_funcs = n_basefunctions(get_functionspace(fe_v))
    @assert length(u) == n_base_funcs
    @assert length(grad) == dim
    dN = shape_gradient(fe_v, q_point)
    fill!(grad, 0.0)
    @inbounds for k in 1:dim # Loop order checked
        @simd for i in 1:n_base_funcs
            grad[k] += dN[k, i] * u[i]
        end
    end
    return grad
end

# u should be given as [x, y, z, x, y, z, ...]
"""
    function_vector_gradient!(grad::Matrix, fe_v, q_point::Int, u::Vector) -> gradient

Computes the gradient (jacobian) in a quadrature point for a vector valued function. Result
is stored in `grad`.
"""
@inline function function_vector_gradient!{dim, T}(grad::Matrix{T}, fe_v::FEValues{dim}, q_point::Int, u::Vector{T})
    n_base_funcs = n_basefunctions(get_functionspace(fe_v))
    @assert length(u) == dim * n_base_funcs
    @assert size(grad) == (dim, dim)
    dN = shape_gradient(fe_v, q_point)
    fill!(grad, 0.0)

    @inbounds for j in 1:dim, k in 1:dim
        for i in 1:n_base_funcs
            offset = dim*(i-1)
            grad[j, k] += dN[k, i] * u[offset + j]
        end
    end
    return grad
end

# u should be given as [x, y, z, x, y, z, ...]
"""
    function_vector_symmetric_gradient!(grad::Matrix, fe_v, q_point::Int, u::Vector) -> sym_gradient

Computes the symmetric gradient (jacobian) in a quadrature point for a vector valued function.
Result is stored in `grad`.
"""
@inline function function_vector_symmetric_gradient!{dim, T}(grad::Matrix{T}, fe_v::FEValues{dim}, q_point::Int, u::Vector{T})
    n_base_funcs = n_basefunctions(get_functionspace(fe_v))
    @assert length(u) == dim * n_base_funcs
    @assert size(grad) == (dim, dim)
    dN = shape_gradient(fe_v, q_point)
    fill!(grad, 0.0)

    @inbounds for i in 1:n_base_funcs
        offset = dim * (i-1)
        for j in 1:dim
            grad[j, j] += dN[j, i] * u[offset + j]
        end

        for j in 1:dim, k in j+1:dim,
            v = 0.5 * (dN[j, i] * u[offset + k] + dN[k, i] * u[offset + j])
            grad[j, k] += v
            grad[k, j] += v
        end
    end
    return grad
end

# u should be given as [x, y, z, x, y, z, ...]
"""
    function_vector_divergence(fe_v, q_point::Int, u::Vector) -> divergence

Computes the divergence in a quadrature point for a vector valued function.
"""
@inline function function_vector_divergence{dim, T}(fe_v::FEValues{dim}, q_point::Int, u::Vector{T})
    n_base_funcs = n_basefunctions(get_functionspace(fe_v))
    @assert length(u) == dim * n_base_funcs
    dN = shape_gradient(fe_v, q_point)
    div = zero(T)
    @inbounds for i in 1:n_base_funcs
        offset = dim*(i-1)
        for j in 1:dim
            div += dN[j, i] *  u[offset + j]
        end
    end
    return div
end
