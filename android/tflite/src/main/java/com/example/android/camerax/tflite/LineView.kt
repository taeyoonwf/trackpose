package com.example.android.camerax.tflite
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View

class LineView(context: Context, attrs: AttributeSet?) : View(context, attrs) {
    private val paintRoll = Paint()
    private val paintPitch = Paint()
    //private var startX = 0f
    //private var startY = 0f
    //private var endX = 0f
    //private var endY = 0f
    private var dx = 0f
    private var dy = 0f
    private var h = 0f

    private val unt = 200
    private val max_val = 9.8
    private val h_mult = 0.25

    init {
        paintRoll.color = android.graphics.Color.GREEN
        paintRoll.alpha = 128
        paintRoll.strokeWidth = 5f

        paintPitch.color = android.graphics.Color.RED
        paintPitch.alpha = 128
        paintPitch.strokeWidth = 5f
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val cx = canvas.height * 0.5f
        val cy = canvas.width * 0.5f
        //let height = canvas.getHeight()
        //let width = canvas.getWidth()

        val startY = cx - dx
        val endY = cx + dx
        val startX = cy - dy
        val endX = cy + dy
        canvas.drawLine(startX, startY, endX, endY, paintRoll)

        canvas.drawLine(cy + h * cy , cx - unt, cy + h * cy, cx + unt, paintPitch)
    }

    fun setAccelerometer(x: Float, y: Float, z: Float) {
        this.dx = (Math.cos(y / max_val * Math.PI / 2) * unt).toFloat()
        this.dy = (Math.sin(y / max_val * Math.PI / 2) * unt).toFloat()
        this.h = (z / max_val * h_mult).toFloat()
        invalidate() // This will trigger a redraw
    }
}
