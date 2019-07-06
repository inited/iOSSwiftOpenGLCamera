//
//  OpenGLView.swift
//  iOSSwiftOpenGLCamera
//
//  Created by Bradley Griffith on 7/1/14.
//  Copyright (c) 2014 Bradley Griffith. All rights reserved.
//

import Foundation
import UIKit
import QuartzCore
import OpenGLES
import GLKit
import CoreMedia
import AVFoundation


struct Vertex {
	var Position: (CFloat, CFloat, CFloat)
	var TexCoord: (CFloat, CFloat)
}

var Vertices: (Vertex, Vertex, Vertex, Vertex) = (
	Vertex(Position: (1, -1, 0) , TexCoord: (1, 1)),
	Vertex(Position: (1, 1, 0)  , TexCoord: (1, 0)),
	Vertex(Position: (-1, 1, 0) , TexCoord: (0, 0)),
	Vertex(Position: (-1, -1, 0), TexCoord: (0, 1))
)

var Indices: (GLubyte, GLubyte, GLubyte, GLubyte, GLubyte, GLubyte) = (
	0, 1, 2,
	2, 3, 0
)


class OpenGLView: UIView {
	
	var eaglLayer: CAEAGLLayer!
	var context: EAGLContext!
	var colorRenderBuffer: GLuint = GLuint()
	var positionSlot: GLuint = GLuint()
	var texCoordSlot: GLuint = GLuint()
	var textureUniform: GLuint = GLuint()
	var timeUniform: GLuint = GLuint()
	var showShaderBoolUniform: GLuint = GLuint()
	var indexBuffer: GLuint = GLuint()
	var vertexBuffer: GLuint = GLuint()
	var unmanagedVideoTexture: Unmanaged<CVOpenGLESTexture>?
    var videoTexture: CVOpenGLESTexture?
	var videoTextureID: GLuint?
	var unmanagedCoreVideoTextureCache: Unmanaged<CVOpenGLESTextureCache>?
    var coreVideoTextureCache: CVOpenGLESTextureCache?
	
	var textureWidth: UInt?
	var textureHeight: UInt?
	
	var time: GLfloat = 0.0
	var showShader: GLfloat = 1.0
	
	var frameTimestamp: Double = 0.0
	
	/* Class Methods
	------------------------------------------*/
	
	override final class var layerClass: AnyClass {
		// In order for our view to display OpenGL content, we need to set it's
		//   default layer to be a CAEAGLayer
		return CAEAGLLayer.self
	}
	
	
	/* Lifecycle
	------------------------------------------*/
	
    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)!
		
		setupLayer()
		setupContext()
		setupRenderBuffer()
		setupFrameBuffer()
		compileShaders()
		setupVBOs()
		setupDisplayLink()
		
        self.contentScaleFactor =  UIScreen.main.scale
	}

	
	/* Setup Methods
	------------------------------------------*/
	
	func setupLayer() {
		// CALayer's are, by default, non-opaque, which is 'bad for performance with OpenGL',
		//   so let's set our CAEAGLLayer layer to be opaque.
        eaglLayer = layer as! CAEAGLLayer
        eaglLayer.isOpaque = true

	}
	
	func setupContext() {
		// Just like with CoreGraphics, in order to do much with OpenGL, we need a context.
		//   Here we create a new context with the version of the rendering API we want and
		//   tells OpenGL that when we draw, we want to do so within this context.
        let api: EAGLRenderingAPI = EAGLRenderingAPI.openGLES2
        context = EAGLContext(api: api)
		
        if (self.context == nil) {
			print("Failed to initialize OpenGLES 2.0 context!")
			exit(1)
		}
		
        if (!EAGLContext.setCurrent(context)) {
			print("Failed to set current OpenGL context!")
			exit(1)
		}

        CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, nil, context, nil, &coreVideoTextureCache)
	}

	func setupRenderBuffer() {
		// A render buffer is an OpenGL objec that stores the rendered image to present to the screen.
		//   OpenGL will create a unique identifier for a render buffer and store it in a GLuint.
		//   So we call the glGenRenderbuffers function and pass it a reference to our colorRenderBuffer.
		glGenRenderbuffers(1, &colorRenderBuffer)
		// Then we tell OpenGL that whenever we refer to GL_RENDERBUFFER, it should treat that as our colorRenderBuffer.
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), colorRenderBuffer)
		// Finally, we tell our context that the render buffer for our layer is our colorRenderBuffer.
        context.renderbufferStorage(Int(GL_RENDERBUFFER), from:eaglLayer)
	}
	
	func setupFrameBuffer() {
		// A frame buffer is an OpenGL object for storage of a render buffer... amongst other things (tm).
		//   OpenGL will create a unique identifier for a frame vuffer and store it in a GLuint. So we
		//   make a GLuint and pass it to the glGenFramebuffers function to keep this identifier.
		var frameBuffer: GLuint = GLuint()
		glGenFramebuffers(1, &frameBuffer)
		// Then we tell OpenGL that whenever we refer to GL_FRAMEBUFFER, it should treat that as our frameBuffer.
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), frameBuffer)
		// Finally we tell the frame buffer that it's GL_COLOR_ATTACHMENT0 is our colorRenderBuffer. Oh.
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_RENDERBUFFER), colorRenderBuffer)
	}
	
    
    func compileShader(_ shaderName: String, shaderType: GLenum) -> GLuint {
        
        // Get NSString with contents of our shader file.
        let shaderPath = Bundle.main.path(forResource: shaderName, ofType: "glsl")
        let shaderString = try! String(contentsOfFile: shaderPath!)
        
        // Tell OpenGL to create an OpenGL object to represent the shader, indicating if it's a vertex or a fragment shader.
        let shaderHandle = glCreateShader(shaderType)
        
        if shaderHandle == 0 {
            NSLog("Couldn't create shader")
        }
        
        // Conver shader string to CString and call glShaderSource to give OpenGL the source for the shader.
        let cString = shaderString.utf8CString
        cString.withUnsafeBufferPointer { (pointer) -> Void in
            pointer.withMemoryRebound(to: GLchar.self) { (p: UnsafeBufferPointer<GLchar>) -> Void in
                var p: UnsafePointer<GLchar>? = p.baseAddress
                var shaderStringLength: GLint = GLint(Int32(shaderString.utf8CString.count))
                glShaderSource(shaderHandle, 1, &p, &shaderStringLength)
                
                // Tell OpenGL to compile the shader.
                glCompileShader(shaderHandle)
                
                // But compiling can fail! If we have errors in our GLSL code, we can here and output any errors.
                var compileSuccess: GLint = GLint()
                glGetShaderiv(shaderHandle, GLenum(GL_COMPILE_STATUS), &compileSuccess)
                if (compileSuccess == GL_FALSE) {
                    var buffer: [GLchar] = Array(repeating: 0, count: 1024)
                    var length: GLsizei = 0
                    glGetShaderInfoLog(shaderHandle, GLsizei(buffer.count), &length, &buffer)
                    print("Failed to compile shader: \(String(cString: buffer))")
                    
                    exit(1)
                }
            }
        }
        
        return shaderHandle
    }
	
	func compileShaders() {
		
		// Compile our vertex and fragment shaders.
        let vertexShader: GLuint = compileShader("SimpleVertex", shaderType: GLenum(GL_VERTEX_SHADER))
        let fragmentShader: GLuint = compileShader("SimpleFragment", shaderType: GLenum(GL_FRAGMENT_SHADER))
		
		// Call glCreateProgram, glAttachShader, and glLinkProgram to link the vertex and fragment shaders into a complete program.
        let programHandle: GLuint = glCreateProgram()
		glAttachShader(programHandle, vertexShader)
		glAttachShader(programHandle, fragmentShader)
		glLinkProgram(programHandle)
		
		// Check for any errors.
		var linkSuccess: GLint = GLint()
		glGetProgramiv(programHandle, GLenum(GL_LINK_STATUS), &linkSuccess)
		if (linkSuccess == GL_FALSE) {
			print("Failed to create shader program!")
			// TODO: Actually output the error that we can get from the glGetProgramInfoLog function.
			exit(1);
		}
		
		// Call glUseProgram to tell OpenGL to actually use this program when given vertex info.
		glUseProgram(programHandle)
		
		// Finally, call glGetAttribLocation to get a pointer to the input values for the vertex shader, so we
		//  can set them in code. Also call glEnableVertexAttribArray to enable use of these arrays (they are disabled by default).
        positionSlot = GLuint(glGetAttribLocation(programHandle, "Position"))
		glEnableVertexAttribArray(positionSlot)
		
		texCoordSlot = GLuint(glGetAttribLocation(programHandle, "TexCoordIn"))
		glEnableVertexAttribArray(texCoordSlot);
		
		textureUniform = GLuint(glGetUniformLocation(programHandle, "Texture"))
		
		//timeUniform = GLuint(glGetUniformLocation(programHandle, "time"))
		
		showShaderBoolUniform = GLuint(glGetUniformLocation(programHandle, "showShader"))
	}
	
	// Setup Vertex Buffer Objects
	func setupVBOs() {
		glGenBuffers(1, &vertexBuffer)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vertexBuffer)
        glBufferData(GLenum(GL_ARRAY_BUFFER), MemoryLayout.size(ofValue: Vertices), &Vertices, GLenum(GL_STATIC_DRAW))
		
		glGenBuffers(1, &indexBuffer)
		glBindBuffer(GLenum(GL_ELEMENT_ARRAY_BUFFER), indexBuffer)
		glBufferData(GLenum(GL_ELEMENT_ARRAY_BUFFER), MemoryLayout.size(ofValue: Indices), &Indices, GLenum(GL_STATIC_DRAW))
	}
	
	func setupDisplayLink() {
        let displayLink: CADisplayLink = CADisplayLink(target: self, selector: #selector(OpenGLView.render))
        displayLink.add(to: RunLoop.current, forMode: RunLoop.Mode.default)
	}
	
	
	/* Helper Methods
	------------------------------------------*/
	
	func getTextureFromImageWithName(fileName: NSString) -> GLuint {
		
        guard let spriteImage: CGImage = (UIImage(named: fileName as String)?.cgImage) else {
			print("Failed to load image!")
			exit(1)
		}
		
        let width: Int = spriteImage.width
        let height: Int = spriteImage.height
        let spriteData = calloc(width * height * 4, MemoryLayout<GLubyte>.size)
        guard let spriteContext: CGContext = CGContext(data: spriteData,
                                            width: width,
                                            height: height,
                                            bitsPerComponent: 8,
                                            bytesPerRow: width * 4,
                                            space: spriteImage.colorSpace!,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                                                print("Failed to create image context!")
                                                exit(1)
        }
        
        
        spriteContext.draw(spriteImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var texName: GLuint = GLuint()
		glGenTextures(1, &texName)
		glBindTexture(GLenum(GL_TEXTURE_2D), texName)
		
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_NEAREST)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA, GLsizei(width), GLsizei(height), 0, GLenum(GL_RGBA), UInt32(GL_UNSIGNED_BYTE), spriteData)
		
		free(spriteData)
		return texName
	}
	
	func cleanupVideoTextures() {
        if ((videoTexture) != nil) {
			videoTexture = nil
		}
        CVOpenGLESTextureCacheFlush(coreVideoTextureCache!, 0)
	}
	
	func getTextureFromSampleBuffer(sampleBuffer: CMSampleBuffer!) -> GLuint {
		cleanupVideoTextures()
		
        let imageBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
		let textureWidth = CVPixelBufferGetWidth(imageBuffer)
		let textureHeight = CVPixelBufferGetHeight(imageBuffer)

        CVPixelBufferLockBaseAddress(imageBuffer, [])
		CVOpenGLESTextureCacheCreateTextureFromImage(
										kCFAllocatorDefault,
                                        coreVideoTextureCache!,
										imageBuffer,
										nil,
                                        GLenum(GL_TEXTURE_2D),
										GL_RGBA,
										GLsizei(textureWidth),
										GLsizei(textureHeight),
										GLenum(GL_BGRA),
										UInt32(GL_UNSIGNED_BYTE),
										0,
										&videoTexture
									)
				
		var textureID: GLuint = GLuint()
        textureID = CVOpenGLESTextureGetName(videoTexture!);
		glBindTexture(GLenum(GL_TEXTURE_2D), textureID);
		
		glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR);
		glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR);
		glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE);
		glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE);
		
		
        CVPixelBufferUnlockBaseAddress(imageBuffer, [])
		
		
		return textureID
	}
	
	func updateUsingSampleBuffer(sampleBuffer: CMSampleBuffer!) {
		DispatchQueue.main.async {
            self.videoTextureID = self.getTextureFromSampleBuffer(sampleBuffer: sampleBuffer)
		}
	}
	
	func shouldShowShader(show: Bool) {
		showShader = show ? 1.0 : 0.0
	}
	
    @objc func render(displayLink: CADisplayLink) {
		
        if (textureWidth != nil) && (textureHeight != nil) {
			var ratio = CGFloat(frame.size.height) / CGFloat(textureHeight!)
			glViewport(0, 0, GLint(CGFloat(textureWidth!) * ratio), GLint(CGFloat(textureHeight!) * ratio))
		}
		else {
			//glViewport(0, 0, GLint(frame.size.width), GLint(frame.size.height))
            glViewport(0, 35, 480, 445) // iPhone 7 full screen without bottom bar
		}
		
		glVertexAttribPointer(positionSlot, 3, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(MemoryLayout<Vertex>.size), nil)
		
        let ptr = UnsafeRawPointer(bitPattern: MemoryLayout<CFloat>.size * 3)
		glVertexAttribPointer(texCoordSlot, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), GLsizei(MemoryLayout<Vertex>.size), ptr)
		glActiveTexture(UInt32(GL_TEXTURE0))
        if (videoTextureID != nil) {
			glBindTexture(GLenum(GL_TEXTURE_2D), videoTextureID!)
            glUniform1i(GLint(textureUniform), 0)
		}
		
		glUniform1f(GLint(showShaderBoolUniform), showShader)

        glDrawElements(GLenum(GL_TRIANGLES), GLsizei(MemoryLayout.size(ofValue: Indices) / MemoryLayout<GLubyte>.size), GLenum(GL_UNSIGNED_BYTE), nil)
		
		context.presentRenderbuffer(Int(GL_RENDERBUFFER))
	}
}
