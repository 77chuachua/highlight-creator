// hc-gpu: GPU shader management.
// Compiles GLSL/HLSL to platform-specific shader binaries via naga.

/// Shader types supported by the pipeline.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShaderType {
    Vertex,
    Fragment,
    Compute,
}

/// A compiled shader ready for GPU execution.
#[derive(Debug, Clone)]
pub struct CompiledShader {
    pub shader_type: ShaderType,
    pub entry_point: String,
    /// Platform-specific binary (SPIR-V, MSL, DXIL).
    pub binary: Vec<u8>,
}

/// Compile a GLSL shader source to the platform's native format.
pub fn compile_glsl(
    _source: &str,
    _shader_type: ShaderType,
    _entry_point: &str,
) -> anyhow::Result<CompiledShader> {
    // Phase 3: use naga to parse GLSL → SPIR-V → Metal/D3D.
    anyhow::bail!("Shader compilation not yet implemented (Phase 3)")
}
