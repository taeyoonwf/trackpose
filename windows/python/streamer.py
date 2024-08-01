import argparse

import cv2
import zmq

import time
import json


PORT = '5555'
SERVER_ADDRESS = 'localhost'

def image_to_string(image):
    import base64
    encode_param = [int(cv2.IMWRITE_JPEG_QUALITY), 30]
    encoded, buffer = cv2.imencode('.jpg', image, encode_param)
    return base64.b64encode(buffer).decode('utf-8')


class Streamer:
    def __init__(self, width, height, server_address=SERVER_ADDRESS, port=PORT):
        context = zmq.Context()
        self.footage_socket = context.socket(zmq.PUB)
        self.footage_socket.connect('tcp://' + server_address + ':' + port)
        self.keep_running = True
        self.width = width
        self.height = height

    def start(self):
        vid = cv2.VideoCapture(0, cv2.CAP_DSHOW)
        vid.set(cv2.CAP_PROP_FRAME_WIDTH, self.width)
        vid.set(cv2.CAP_PROP_FRAME_HEIGHT, self.height)

        last = time.time()
        last_timestamp = int(last * 1e3)
        #last = datetime.now()
        fps = 30
        fps_timesum, fps_timecnt = 0, 0
        while self.footage_socket and self.keep_running:
            curr = time.time()
            delta = curr - last
            last = curr
            if delta < 1 / fps:
                rem = 1 / fps - delta
                #print(f'rem : {rem}')
                time.sleep(rem)

            #time.sleep(0.1)
            #print("here1")
            try:
                ret, frame = vid.read()
                image_as_string = image_to_string(frame)
                timestamp = int(time.time() * 1e3)
                fps_timesum += timestamp - last_timestamp
                fps_timecnt += 1
                if fps_timesum > 5000:
                    print(f'fps : {1000 / (fps_timesum / fps_timecnt)}')
                    fps_timesum, fps_timecnt = 0, 0
                #print(f'fps : {1000 / (timestamp - last_timestamp)}')
                self.footage_socket.send_string(json.dumps({
                    'timestamp': timestamp,
                    'frame': image_as_string
                }))
                last_timestamp = timestamp
                cv2.imshow("sender\'s frame", frame)
                cv2.waitKey(1)
            except KeyboardInterrupt:
                cv2.destroyAllWindows()
                break

        print("Streaming Stopped!")
        vid.release()
        cv2.destroyAllWindows()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('-s', '--server',
                        help='IP Address of the server which you want to connect to',
                        required=True)
    parser.add_argument('-p', '--port',
                        help='The port which you want the Streaming Server to use, default'
                             ' is ' + PORT, required=False)
    parser.add_argument('-x', '--width',
                        help='The width which you want to use for the video capture, default'
                             ' is ' + str(640), required=False, type=int, default=640)
    parser.add_argument('-y', '--height',
                        help='The height which you want to use for the video capture, default'
                             ' is ' + str(480), required=False, type=int, default=480)

    args = parser.parse_args()

    port = args.port if args.port else PORT
    server_address = args.server if args.server else SERVER_ADDRESS
    width = args.width if args.width else 640
    height = args.height if args.height else 480

    streamer = Streamer(width, height, server_address, port)
    streamer.start()


if __name__ == '__main__':
    main()