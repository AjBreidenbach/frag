import
  logging

import 
    glm, 
    opengl

import 
    ../../assets/asset,
    ../../graphics,
    ibo, 
    mesh, 
    ../shader, 
    texture,
    texture_region, 
    vbo, 
    vertex

type
  SpriteBatch* = ref object
    mesh: Mesh
    vertices: seq[Vertex]
    maxSprites: int
    lastTexture: Texture
    projectionMatrix: Mat4x4[GLfloat]
    transformMatrix : Mat4x4[GLfloat]
    combinedMatrix: Mat4x4[GLfloat]
    shader: ShaderProgram
    drawing: bool
    blendSrcFunc*, blendDstFunc*: BlendFunc
    blendingEnabled*: bool

proc createDefaultShader() : ShaderProgram =
  let vertexShaderSource = """
    #version 330 core
    layout (location = 0) in vec3 position;
    layout (location = 1) in vec2 texCoords;
    layout (location = 2) in vec4 color;
    out vec2 TexCoords;
    out vec4 Color;
    uniform mat4 model;
    uniform mat4 projection;
    void main()
    {
        Color = color;
        TexCoords = texCoords;
        gl_Position = projection * model * vec4(position, 1.0);
    }
  """
  let fragmentShaderSource = """
    #version 330 core
    in vec2 TexCoords;
    in vec4 Color;
    out vec4 color;
    uniform sampler2D image;
    uniform vec3 spriteColor;
    const float smoothing = 1.0/16.0;
    void main()
    {
        //float distance = texture(image, TexCoords).a;    
        //float alpha = smoothstep(0.5 - smoothing, 0.5 + smoothing, distance);
        //color = vec4(Color.xyz, Color.w * alpha);
        color =  Color * texture(image, TexCoords);
    }  
  """

  let shaderProgram = createShaderProgram(vertexShaderSource, fragmentShaderSource)
  if not shaderProgram.isCompiled:
    error "Error compiling shader : " & shaderProgram.log
  return shaderProgram


proc setupMatrices(spriteBatch: SpriteBatch) =
  spriteBatch.combinedMatrix = spriteBatch.projectionMatrix * spriteBatch.transformMatrix
  spriteBatch.shader.setUniformMatrix("projection", spriteBatch.combinedMatrix)
  spriteBatch.shader.setUniformi("image", 0)

proc flush(spriteBatch: SpriteBatch) =
  if spriteBatch.lastTexture.isNil:
    return

  if spriteBatch.blendingEnabled:
    glEnable(GL_BLEND)
    glBlendFunc(GLenum spriteBatch.blendSrcFunc, GLenum spriteBatch.blendDstFunc)
  

  spriteBatch.lastTexture.`bind`()

  spriteBatch.mesh.`bind`()
  spriteBatch.mesh.render()

  if spriteBatch.blendingEnabled:
    glDisable(GL_BLEND)

proc switchTexture(spriteBatch: SpriteBatch, texture: Texture) =
  flush(spriteBatch)
  spriteBatch.lastTexture = texture

proc drawTextureRegion*(spriteBatch: var SpriteBatch, textureRegion: TextureRegion, x, y, width, height: float, color: Vec4f = vec4f(1.0, 1.0, 1.0, 1.0f)) =
  if not spriteBatch.drawing:
    error "Spritebatch not in drawing mode. Call begin before calling draw."
    return

  let texture = textureRegion.texture
  if texture != spriteBatch.lastTexture:
    switchTexture(spriteBatch, texture)
  
  var m = mat4[GLfloat](1.0)
  spriteBatch.shader.setUniformMatrix("model", m)

  let u = textureRegion.u
  let v = textureRegion.v2
  let u2 = textureRegion.u2
  let v2 = textureRegion.v
  
  spritebatch.vertices.add(newVertex(
    vec3f(x, y, 0.0)
    , vec2f(u, v)
    , color
  ))

  spritebatch.vertices.add(newVertex(
    vec3f(x, y + height, 0.0)
    , vec2f(u, v2)
    , color
  ))

  spritebatch.vertices.add(newVertex(
    vec3f(x + width, y + height, 0.0)
    , vec2f(u2, v2)
    , color
  ))

  spritebatch.vertices.add(newVertex(
    vec3f(x + width, y, 0.0)
    , vec2f(u2, v)
    , color
  ))

  spriteBatch.mesh.addVertices(spritebatch.vertices)
  spriteBatch.vertices.setLen(0)

  if int(spriteBatch.mesh.indexCount() / 6) >= spriteBatch.maxSprites:
    flush(spriteBatch)

proc draw*(spriteBatch: var SpriteBatch, textureRegion: TextureRegion, x, y: float) =
  drawTextureRegion(spriteBatch, textureRegion, x, y, float textureRegion.regionWidth, float textureRegion.regionHeight)


proc draw*(spriteBatch: SpriteBatch, texture: Texture, x, y, width, height: float, color: Vec4f = vec4f(1.0, 1.0, 1.0, 1.0f)) =
  if not spriteBatch.drawing:
    error "Spritebatch not in drawing mode. Call begin before calling draw."
    return

  if texture != spriteBatch.lastTexture:
    switchTexture(spriteBatch, texture)

  var m = mat4[GLfloat](1.0)
  spriteBatch.shader.setUniformMatrix("model", m)
  
  spritebatch.vertices.add(newVertex(
    vec3f(x, y, 0.0)
    , vec2f(0.0, 0.0)
    , color
  ))

  spritebatch.vertices.add(newVertex(
    vec3f(x, y + height, 0.0)
    , vec2f(0.0, 1.0)
    , color
  ))

  spritebatch.vertices.add(newVertex(
    vec3f(x + width, y + height, 0.0)
    , vec2f(1.0, 1.0)
    , color
  ))

  spritebatch.vertices.add(newVertex(
    vec3f(x + width, y, 0.0)
    , vec2f(1.0, 0.0)
    , color
  ))

  spriteBatch.mesh.addVertices(spritebatch.vertices)
  spriteBatch.vertices.setLen(0)

  if int(spriteBatch.mesh.indexCount() / 6) >= spriteBatch.maxSprites:
    flush(spriteBatch)

proc init*(spriteBatch: SpriteBatch, maxSprites: int, defaultShader: ShaderProgram) =
  spriteBatch.drawing = false
  spriteBatch.maxSprites = maxSprites
  spriteBatch.vertices = @[]
  spriteBatch. mesh = newMesh(true)

  var i = 0
  var j : GLushort = 0
  var indices : seq[GLushort] = @[]
  while i < maxSprites:
    indices.add(j)
    indices.add(j + 1)
    indices.add(j + 2)
    indices.add(j + 2)
    indices.add(j + 3)
    indices.add(j)
    inc(j, 4)
    inc(i, 6)

  spriteBatch.mesh.setIndices(indices)

  if defaultShader.isNil:
    spriteBatch.shader = createDefaultShader()
  else:
    spriteBatch.shader = defaultShader

  spriteBatch.projectionMatrix = ortho[GLfloat](0, 960, 540, 0, -1.0, 1.0)
  spriteBatch.transformMatrix = mat4[GLfloat]()
  spriteBatch.transformMatrix = scale(spriteBatch.transformMatrix, vec3f(1, 1, 1.0))

proc begin*(spriteBatch: SpriteBatch) =
  if spriteBatch.drawing:
    error "Spritebatch is already in drawing mode. Call end before calling begin."
    return
  glDepthMask(false)
  spriteBatch.shader.begin()

  spriteBatch.setupMatrices()

  spriteBatch.drawing = true

proc `end`*(spriteBatch: SpriteBatch) =
  if not spriteBatch.drawing:
    error "Spritebatch is not currently in drawing mode. Call begin before calling end."
    return
  
  if spriteBatch.mesh.indexCount() > 0:
    flush(spriteBatch)

  spriteBatch.lastTexture = nil
  spriteBatch.drawing = false

  glDepthMask(true)

  spriteBatch.shader.`end`()

proc setProjectionMatrix*(spriteBatch: SpriteBatch, projection: Mat4x4[GLfloat]) =
  if spriteBatch.drawing:
    flush(spriteBatch)
  
  spriteBatch.projectionMatrix = projection
  if spriteBatch.drawing:
    spriteBatch.setupMatrices()