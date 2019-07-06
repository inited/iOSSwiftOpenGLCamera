precision mediump float;

uniform sampler2D Texture;
uniform float showShader;
varying vec2 CameraTextureCoord;

void main() {
	if (showShader > 0.5) {
        vec4 pix = texture2D(Texture, CameraTextureCoord);
        gl_FragColor = vec4(pix.g, pix.g, pix.g, pix.a);
    } else {
		gl_FragColor = texture2D(Texture, CameraTextureCoord);
	}
}
