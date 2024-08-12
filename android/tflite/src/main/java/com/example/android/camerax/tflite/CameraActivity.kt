/*
 * Copyright 2020 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.example.android.camerax.tflite

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Matrix
import android.graphics.RectF
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.util.Log
import android.util.Size
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.AspectRatio
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.android.example.camerax.tflite.databinding.ActivityCameraBinding
import mu.KotlinLogging
import org.json.JSONArray
import org.json.JSONObject
import org.tensorflow.lite.DataType
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.nnapi.NnApiDelegate
import org.tensorflow.lite.support.common.FileUtil
import org.tensorflow.lite.support.common.ops.NormalizeOp
import org.tensorflow.lite.support.image.ImageProcessor
import org.tensorflow.lite.support.image.TensorImage
import org.tensorflow.lite.support.image.ops.ResizeOp
import org.tensorflow.lite.support.image.ops.ResizeWithCropOrPadOp
import org.tensorflow.lite.support.image.ops.Rot90Op
import org.zeromq.SocketType
import org.zeromq.ZMQ
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random


/** Activity that displays the camera and performs object detection on the incoming frames */
class CameraActivity : AppCompatActivity(), SensorEventListener {

    private lateinit var activityCameraBinding: ActivityCameraBinding

    private lateinit var bitmapBuffer: Bitmap

    private val executor = Executors.newSingleThreadExecutor()
    private val permissions = listOf(Manifest.permission.CAMERA)
    private val permissionsRequestCode = Random.nextInt(0, 10000)

    private var lensFacing: Int = CameraSelector.LENS_FACING_FRONT //.LENS_FACING_BACK
    private val isFrontFacing get() = lensFacing == CameraSelector.LENS_FACING_FRONT

    private var pauseAnalysis = false
    private var imageRotationDegrees: Int = 0
    private val tfImageBuffer = TensorImage(DataType.UINT8)

    private val logger = KotlinLogging.logger {}
    private var zmqContext = ZMQ.context(1)
    private var footageSocket = zmqContext.socket(SocketType.PUB)
    private val viewer_server_address = "192.168.0.1" // 13.114" //128" //135" //114" //103" //135"
    private val viewer_port = "5555"
    private val base36code = "1qazxsw23edcvfr45tgbnhy67ujmki89olp0"

    //var bluetoothManager: BluetoothManager = getSystemService(BLUETOOTH_SERVICE) as BluetoothManager
    //var bluetoothAdapter: BluetoothAdapter = bluetoothManager.adapter
    private lateinit var sensorManager: SensorManager
    private var accelerometer: Sensor? = null

    private val tfImageProcessor by lazy {
        val cropSize = minOf(bitmapBuffer.width, bitmapBuffer.height)
        ImageProcessor.Builder()
            .add(ResizeWithCropOrPadOp(cropSize, cropSize))
            .add(ResizeOp(
                tfInputSize.height, tfInputSize.width, ResizeOp.ResizeMethod.NEAREST_NEIGHBOR))
            .add(Rot90Op(-imageRotationDegrees / 90))
            .add(NormalizeOp(0f, 1f))
            .build()
    }

    private val nnApiDelegate by lazy  {
        NnApiDelegate()
    }

    private val tflite by lazy {
        Interpreter(
            FileUtil.loadMappedFile(this, MODEL_PATH),
            Interpreter.Options().addDelegate(nnApiDelegate))
    }
    private val detector by lazy {
        ObjectDetectionHelper(
            tflite,
            FileUtil.loadLabels(this, LABELS_PATH)
        )
    }

    private val tfInputSize by lazy {
        val inputIndex = 0
        val inputShape = tflite.getInputTensor(inputIndex).shape()
        Size(inputShape[2], inputShape[1]) // Order of axis is: {1, height, width, 3}
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        activityCameraBinding = ActivityCameraBinding.inflate(layoutInflater)
        setContentView(activityCameraBinding.root)
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        activityCameraBinding.cameraCaptureButton.setOnClickListener {

            // Disable all camera controls
            it.isEnabled = false

            if (pauseAnalysis) {
                // If image analysis is in paused state, resume it
                pauseAnalysis = false
                activityCameraBinding.imagePredicted.visibility = View.GONE

            } else {
                // Otherwise, pause image analysis and freeze image
                pauseAnalysis = true
                val matrix = Matrix().apply {
                    postRotate(imageRotationDegrees.toFloat())
                    if (isFrontFacing) postScale(-1f, 1f)
                }
                val uprightImage = Bitmap.createBitmap(
                    bitmapBuffer, 0, 0, bitmapBuffer.width, bitmapBuffer.height, matrix, true)
                activityCameraBinding.imagePredicted.setImageBitmap(uprightImage)
                activityCameraBinding.imagePredicted.visibility = View.VISIBLE
            }

            // Re-enable camera controls
            it.isEnabled = true
        }

        footageSocket.connect("tcp://" + viewer_server_address + ":" + viewer_port)

        /* if (bluetoothAdapter == null) {
            // Device doesn't support Bluetooth
        } */
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)

        if (accelerometer != null) {
            sensorManager.registerListener(this, accelerometer, SensorManager.SENSOR_DELAY_NORMAL)
        } else {
            Toast.makeText(this, "Accelerometer not available", Toast.LENGTH_SHORT).show()
        }

        activityCameraBinding.networkCode?.addTextChangedListener(object : TextWatcher {
            override fun afterTextChanged(s: Editable?) {
                Log.d(TAG, "${s.toString()}")
                val code = s.toString()
                if (code.length == 4) {
                    val id0 = base36code.indexOfFirst { it == code.get(0) }
                    val id1 = base36code.indexOfFirst { it == code.get(1) }
                    val id2 = base36code.indexOfFirst { it == code.get(2) }
                    val id3 = base36code.indexOfFirst { it == code.get(3) }
                    if ((id0 and 24) == 16) {
                        val n2 = ((id0 and 7) shl 5) or (id1)
                        val n3 = (id2 shl 4) or id3

                        if ((n2 in (0..255)) && (n3 in (0..255))) {
                            runOnUiThread {
                                footageSocket.close()
                                zmqContext.close()
                                zmqContext = ZMQ.context(1)
                                footageSocket = zmqContext.socket(SocketType.PUB)
                                footageSocket.connect("tcp://192.168." + n2.toString() + "." + n3.toString() + ":" + viewer_port)
                            }
                        }
                    }
                }
            }

            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {
            }

            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
            }
        })
    }

    override fun onDestroy() {

        // Terminate all outstanding analyzing jobs (if there is any).
        executor.apply {
            shutdown()
            awaitTermination(1000, TimeUnit.MILLISECONDS)
        }

        // Release TFLite resources.
        tflite.close()
        nnApiDelegate.close()

        super.onDestroy()
    }

    /** Declare and bind preview and analysis use cases */
    @SuppressLint("UnsafeExperimentalUsageError")
    private fun bindCameraUseCases() = activityCameraBinding.viewFinder.post {

        val cameraProviderFuture = ProcessCameraProvider.getInstance(this)
        cameraProviderFuture.addListener ({

            // Camera provider is now guaranteed to be available
            val cameraProvider = cameraProviderFuture.get()

            // Set up the view finder use case to display camera preview
            val preview = Preview.Builder()
                .setTargetAspectRatio(AspectRatio.RATIO_4_3)
                .setTargetRotation(activityCameraBinding.viewFinder.display.rotation)
                .build()

            // Set up the image analysis use case which will process frames in real time
            val imageAnalysis = ImageAnalysis.Builder()
                .setTargetAspectRatio(AspectRatio.RATIO_4_3)
                .setTargetRotation(activityCameraBinding.viewFinder.display.rotation)
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                .build()

            var frameCounter = 0
            var lastFpsTimestamp = System.currentTimeMillis()

            imageAnalysis.setAnalyzer(executor, ImageAnalysis.Analyzer { image ->
                if (!::bitmapBuffer.isInitialized) {
                    // The image rotation and RGB image buffer are initialized only once
                    // the analyzer has started running
                    imageRotationDegrees = image.imageInfo.rotationDegrees
                    bitmapBuffer = Bitmap.createBitmap(
                        image.width, image.height, Bitmap.Config.ARGB_8888)
                }

                // Early exit: image analysis is in paused state
                if (pauseAnalysis) {
                    image.close()
                    return@Analyzer
                }

                //for (i in 0..10)
                //    Log.d(TAG, "image buffer ${i} ${image.planes[0].buffer[i * 4 + 0]} ${image.planes[0].buffer[i * 4 + 1]} ${image.planes[0].buffer[i * 4 + 2]}")
                // Copy out RGB bits to our shared buffer
                image.use { bitmapBuffer.copyPixelsFromBuffer(image.planes[0].buffer)  }

                //val wrapper = ContextWrapper(baseContext)
                //var file = wrapper.getDir("Images", Context.MODE_PRIVATE)
                //file = File(file,"00000.jpg")
                val stream: ByteArrayOutputStream = ByteArrayOutputStream()
                bitmapBuffer.compress(Bitmap.CompressFormat.JPEG,30, stream)
                val byteArray: ByteArray = stream.toByteArray()

                val currentTimestamp = System.currentTimeMillis()
                val jsonObj: JSONObject = JSONObject()
                //jsonObj.put("timestamp", currentTimestamp)
                val accelerometer: JSONArray = JSONArray()
                accelerometer.put(accX.toDouble())
                accelerometer.put(accY.toDouble())
                accelerometer.put(accZ.toDouble())
                jsonObj.put("accelerometer", accelerometer)
                // jsonObj.put("timestamp", currentTimestamp)
                //jsonObj.
                val frameStr = java.util.Base64.getEncoder().encodeToString(byteArray)
                val frameTest = java.util.Base64.getEncoder().encode(byteArray)
                val frameTestStr = frameTest.toString()
                jsonObj.put("frame", frameStr)
                //{"timestamp": currentTimestamp, "frame": java.util.Base64.getEncoder().encode(byteArray)})
                //stream.write()
                //val jsonStr = jsonObj.toString()
                // "timestamp":1722753514017,
                // "FPS: ${"%.02f".format(fps)}"
                val jsonStr = "{\"timestamp\":${currentTimestamp},${jsonObj.toString().substring(1)}"
                //val jsonStr = "{" + "\"timestamp\":" + currentTimestamp + "," + jsonObj.toString().substring(1) //jsonStr.substring(1)
                //jsonStr.replaceRange(1, 2, "ABCDE")
                // jsonStr.replaceRange(1, 1, "\"timestamp\":" + currentTimestamp + ",")
                runOnUiThread {
                    footageSocket.send(jsonStr)
                }
                //footageSocket.send(jsonStr.toByteArray())
                stream.flush()
                stream.close()

                // Process the image in Tensorflow
                //val tfImage =  tfImageProcessor.process(tfImageBuffer.apply { load(bitmapBuffer) })

                // Perform the object detection for the current frame
                //val predictions = detector.predict(tfImage)

                // Report only the top prediction
                //reportPrediction(predictions.maxByOrNull { it.score })
                reportAccSensor()

                // Compute the FPS of the entire pipeline
                val frameCount = 100
                if (++frameCounter % frameCount == 0) {
                    frameCounter = 0
                    val now = System.currentTimeMillis()
                    val delta = now - lastFpsTimestamp
                    val fps = 1000 * frameCount.toFloat() / delta
                    //Log.d(TAG, "FPS: ${"%.02f".format(fps)} with tensorSize: ${tfImage.width} x ${tfImage.height}")
                    Log.d(TAG, "FPS: ${"%.02f".format(fps)}")
                    lastFpsTimestamp = now
                }
            })

            // Create a new camera selector each time, enforcing lens facing
            val cameraSelector = CameraSelector.Builder().requireLensFacing(lensFacing).build()

            // Apply declared configs to CameraX using the same lifecycle owner
            cameraProvider.unbindAll()
            cameraProvider.bindToLifecycle(
                this as LifecycleOwner, cameraSelector, preview, imageAnalysis)

            // Use the camera object to link our preview use case with the view
            preview.setSurfaceProvider(activityCameraBinding.viewFinder.surfaceProvider)

        }, ContextCompat.getMainExecutor(this))
    }

    private fun reportAccSensor() = activityCameraBinding.viewFinder.post {
        activityCameraBinding.textPrediction.text = "${"%.2f".format(accY)} ${"%.2f".format(accZ)}"
        activityCameraBinding.lineView?.setAccelerometer(accX, accY, accZ)
    }

    private fun reportPrediction(
        prediction: ObjectDetectionHelper.ObjectPrediction?
    ) = activityCameraBinding.viewFinder.post {

        // Early exit: if prediction is not good enough, don't report it
        if (prediction == null || prediction.score < ACCURACY_THRESHOLD) {
            activityCameraBinding.boxPrediction.visibility = View.GONE
            activityCameraBinding.textPrediction.visibility = View.GONE
            return@post
        }

        // Location has to be mapped to our local coordinates
        val location = mapOutputCoordinates(prediction.location)

        // Update the text and UI
        activityCameraBinding.textPrediction.text = "${"%.2f".format(prediction.score)} ${prediction.label}"
        (activityCameraBinding.boxPrediction.layoutParams as ViewGroup.MarginLayoutParams).apply {
            topMargin = location.top.toInt()
            leftMargin = location.left.toInt()
            width = min(activityCameraBinding.viewFinder.width, location.right.toInt() - location.left.toInt())
            height = min(activityCameraBinding.viewFinder.height, location.bottom.toInt() - location.top.toInt())
        }

        // Make sure all UI elements are visible
        activityCameraBinding.boxPrediction.visibility = View.VISIBLE
        activityCameraBinding.textPrediction.visibility = View.VISIBLE
    }

    /**
     * Helper function used to map the coordinates for objects coming out of
     * the model into the coordinates that the user sees on the screen.
     */
    private fun mapOutputCoordinates(location: RectF): RectF {

        // Step 1: map location to the preview coordinates
        val previewLocation = RectF(
            location.left * activityCameraBinding.viewFinder.width,
            location.top * activityCameraBinding.viewFinder.height,
            location.right * activityCameraBinding.viewFinder.width,
            location.bottom * activityCameraBinding.viewFinder.height
        )

        // Step 2: compensate for camera sensor orientation and mirroring
        val isFrontFacing = lensFacing == CameraSelector.LENS_FACING_FRONT
        val correctedLocation = if (isFrontFacing) {
            RectF(
                activityCameraBinding.viewFinder.width - previewLocation.right,
                previewLocation.top,
                activityCameraBinding.viewFinder.width - previewLocation.left,
                previewLocation.bottom)
        } else {
            previewLocation
        }

        // Step 3: compensate for 1:1 to 4:3 aspect ratio conversion + small margin
        val margin = 0.1f
        val requestedRatio = 4f / 3f
        val midX = (correctedLocation.left + correctedLocation.right) / 2f
        val midY = (correctedLocation.top + correctedLocation.bottom) / 2f
        return if (activityCameraBinding.viewFinder.width < activityCameraBinding.viewFinder.height) {
            RectF(
                midX - (1f + margin) * requestedRatio * correctedLocation.width() / 2f,
                midY - (1f - margin) * correctedLocation.height() / 2f,
                midX + (1f + margin) * requestedRatio * correctedLocation.width() / 2f,
                midY + (1f - margin) * correctedLocation.height() / 2f
            )
        } else {
            RectF(
                midX - (1f - margin) * correctedLocation.width() / 2f,
                midY - (1f + margin) * requestedRatio * correctedLocation.height() / 2f,
                midX + (1f - margin) * correctedLocation.width() / 2f,
                midY + (1f + margin) * requestedRatio * correctedLocation.height() / 2f
            )
        }
    }

    override fun onResume() {
        super.onResume()

        sensorManager.registerListener(this, accelerometer, SensorManager.SENSOR_DELAY_NORMAL)
        // Request permissions each time the app resumes, since they can be revoked at any time
        if (!hasPermissions(this)) {
            ActivityCompat.requestPermissions(
                this, permissions.toTypedArray(), permissionsRequestCode)
        } else {
            bindCameraUseCases()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionsRequestCode && hasPermissions(this)) {
            bindCameraUseCases()
        } else {
            finish() // If we don't have the required permissions, we can't run
        }
    }

    /** Convenience method used to check if all permissions required by this app are granted */
    private fun hasPermissions(context: Context) = permissions.all {
        ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
    }

    companion object {
        private val TAG = CameraActivity::class.java.simpleName

        private const val ACCURACY_THRESHOLD = 0.5f
        private const val MODEL_PATH = "coco_ssd_mobilenet_v1_1.0_quant.tflite"
        private const val LABELS_PATH = "coco_ssd_mobilenet_v1_1.0_labels.txt"
    }

    var accX: Float = 0f
    var accY: Float = 0f
    var accZ: Float = 0f

    override fun onSensorChanged(event: SensorEvent?) {
        val x = event!!.values[0]
        val y = event.values[1]
        val z = event.values[2]

        accX = x
        accY = y
        accZ = z
        //if (cnt % 200 == 0) {
            //Log.d(TAG, "XYZ: ${"%.02f".format(x)} ${"%.02f".format(y)} ${"%.02f".format(z)}")
            //logger.debug { x.toString() + ", " + y + ", " + z }
        //}
        if (abs(x) < 1 && abs(y) < 1 && abs(z - SensorManager.GRAVITY_EARTH) < 1) {
            //Toast.makeText(this, "Device is horizontal", Toast.LENGTH_SHORT).show()
        } else {
            //Toast.makeText(this, "Device is not horizontal", Toast.LENGTH_SHORT).show()
        }
    }

    override fun onAccuracyChanged(p0: Sensor?, p1: Int) {
        //TODO("Not yet implemented")
    }

    override fun onPause() {
        super.onPause()
        sensorManager.unregisterListener(this)
    }
}
