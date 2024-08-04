import argparse

import cv2
import numpy as np
import zmq

#from utils import string_to_image
import time
import json
from enum import Enum
import math


PORT = '5555'

def string_to_image(string):
    import numpy as np
    import cv2
    import base64
    img = base64.b64decode(string)
    npimg = np.frombuffer(img, dtype=np.uint8)
    return cv2.flip(cv2.imdecode(npimg, 1), 1)


class StreamSync:
    class Action(Enum):
        PASS = 0
        CONT = 1

    def __init__(self):
        self.STABLE_THRESHOLD = 15 # const
        self.TIME_OUT_MS = 16 # 125 FPS const
        self.DISCONNECT_THRESHOLD = 1 # 1 second
        self.MIN_TIMESTAMP = 17 * 1e11
        self.DIFF_RESET_MULTIPLIER = 4

        self.curr_pub_time = None

        self.curr_sub_time = None
        self.last_pub_time = None
        self.last_sub_time = None
        self.pub_sub_diff = None
        self.pub_sub_diff_stable = 0
        self.time_out_counter = 0

        self.loading_frame = np.zeros((720, 1280, 3))

    def no_poll_in_data(self):
        self.time_out_counter += 1
        if self.time_out_counter > self.DISCONNECT_THRESHOLD * 1000 / self.TIME_OUT_MS:
            return (StreamSync.Action.PASS, self.loading_frame)
            #cv2.imshow("Stream", self.loading_frame)
            #cv2.waitKey(1)
        return (StreamSync.Action.CONT, None)

    def update(self, timestamp):
        curr_pub_time = timestamp
        self.curr_pub_time = timestamp
        self.time_out_counter = 0
        if curr_pub_time < self.MIN_TIMESTAMP:
            print(f'the timestamp of the pub is too much earlier than expected.')
            time.sleep(1)
            return (StreamSync.Action.CONT, None)

        curr_sub_time = round(time.time() * 1e3)
        self.curr_sub_time = curr_sub_time
        curr_pub_sub_diff = curr_sub_time - curr_pub_time
        #print(jsonData['timestamp'])
        if not self.last_pub_time:
            self.last_pub_time, self.last_sub_time = curr_pub_time, curr_sub_time
            self.pub_sub_diff = curr_pub_sub_diff
            return (StreamSync.Action.CONT, None)

        delta_time = curr_pub_time - self.last_pub_time
        if curr_pub_sub_diff < self.pub_sub_diff:
            if curr_pub_sub_diff < self.pub_sub_diff - delta_time * 0.5:
                self.last_pub_time, self.last_sub_time = curr_pub_time, curr_sub_time
                self.pub_sub_diff = curr_pub_sub_diff
                return (StreamSync.Action.CONT, None)
            print(f'{self.pub_sub_diff}, {curr_pub_sub_diff}')
            self.last_pub_time, self.last_sub_time = curr_pub_time, curr_sub_time
            self.pub_sub_diff = curr_pub_sub_diff
            self.pub_sub_diff_stable = 0
        elif curr_pub_sub_diff > max(self.pub_sub_diff, 1) * self.DIFF_RESET_MULTIPLIER:
            self.last_pub_time, self.last_sub_time = curr_pub_time, curr_sub_time
            self.pub_sub_diff = curr_pub_sub_diff
            self.pub_sub_diff_stable = 0
        else:
            self.pub_sub_diff_stable += 1

        #print(self.pub_sub_diff_stable)
        return (StreamSync.Action.PASS, None)


    def render(self, frame):
        self.last_pub_time, self.last_sub_time = self.curr_pub_time, self.curr_sub_time
        if self.pub_sub_diff_stable < self.STABLE_THRESHOLD:
            #cv2.imshow("Stream", string_to_image(self.last_frame))
            #print('last frame')
            return (StreamSync.Action.CONT, None)
        #else:
            #cv2.imshow("Stream", string_to_image(self.curr_frame))
            #ret = (StreamSync.Action.PASS, string_to_image(self.curr_frame))

        #self.last_frame = jsonData['frame']
        image = string_to_image(frame)
        if image.shape != self.loading_frame.shape:
            self.loading_frame = np.zeros(image.shape)
        return (StreamSync.Action.PASS, image)


class StreamViewer:
    def __init__(self, port=PORT):
        """
        Binds the computer to a ip address and starts listening for incoming streams.

        :param port: Port which is used for streaming
        """
        context = zmq.Context()
        self.footage_socket = context.socket(zmq.SUB)
        self.footage_socket.bind('tcp://*:' + port)
        self.footage_socket.setsockopt(zmq.SUBSCRIBE, b'')
        #self.footage_socket.set(zmq.SUBSCRIBE, b'')
        #self.current_frame = None
        self.keep_running = True
        self.debug_count = 0

    def force_packet_delay(self, frame):
        if frame[100, 100].max() != 0:
            self.debug_count += 1
            if self.debug_count > 60:
                self.debug_count = 0
                time.sleep(0.125)

    def draw_accelerometer(self, sensor_value, frame):
        cx, cy = frame.shape[1] * 0.5, frame.shape[0] * 0.5
        unt = 50
        max_val = 9.8
        h_mult = 0.25

        dx = math.cos(-sensor_value[1] / max_val * math.pi / 2) * unt
        dy = math.sin(-sensor_value[1] / max_val * math.pi / 2) * unt
        cv2.line(frame, (int(cx - dx), int(cy - dy)), (int(cx + dx), int(cy + dy)), (0, 255, 0), 1)

        h = sensor_value[2] / max_val * h_mult * cy
        cv2.line(frame, (int(cx - unt), int(cy - h)), (int(cx + unt), int(cy - h)), (0, 0, 255), 1)

    def receive_stream(self, display=True):
        streamSync = StreamSync()
        while self.footage_socket and self.keep_running:
            try:
                if self.footage_socket.poll(streamSync.TIME_OUT_MS) == 0:
                    #print('no poll in data')
                    cont, frame = streamSync.no_poll_in_data()
                    if cont == StreamSync.Action.CONT:
                        continue
                else:
                    #print('poll in data')
                    jsonStr = self.footage_socket.recv_string()
                    # {"timestamp":1722753514017
                    #print(jsonData['timestamp'])
                    if jsonStr[2:11] == 'timestamp' and jsonStr[13:26].isnumeric():
                        timestamp = int(jsonStr[13:26])
                    else:
                        print(f'timestamp is not correct.')
                        time.sleep(1)
                        continue

                    cont, frame = streamSync.update(timestamp = timestamp)
                    if cont == StreamSync.Action.CONT:
                        continue

                    jsonData = json.loads(jsonStr)
                    cont, frame = streamSync.render(jsonData['frame'])
                    if cont == StreamSync.Action.CONT:
                        continue

                    if 'accelerometer' in jsonData:
                        self.draw_accelerometer(jsonData['accelerometer'], frame)

                cv2.imshow("Stream", frame)
                cv2.waitKey(1)
                #self.force_packet_delay(frame)
            except KeyboardInterrupt:
                cv2.destroyAllWindows()
                break
            except e:
                print(e)
                break
        print("Streaming Stopped!")


    def receive_stream_old(self, display=True):
        """
        Displays displayed stream in a window if no arguments are passed.
        Keeps updating the 'current_frame' attribute with the most recent frame, this can be accessed using 'self.current_frame'
        :param display: boolean, If False no stream output will be displayed.
        :return: None
        """
        self.last_frame = None
        self.last_pub_time = None
        self.last_sub_time = None
        self.pub_sub_diff = None
        self.pub_sub_diff_stable = 0
        self.stable_threshold = 15
        self.loading_frame = np.zeros((720, 1280, 3))
        self.time_out_ms = 8 # 125 FPS
        self.disconnect_threshold = 1 # 1 second
        self.time_out_counter = 0
        self.min_timestamp = 17 * 1e11

        while self.footage_socket and self.keep_running:
            try:
                #print('waiting')
                if self.footage_socket.poll(self.time_out_ms) == 0:
                    self.time_out_counter += 1
                    #print('poll = 0')
                    #print(string_to_image(self.last_frame).shape if self.last_frame else 0)
                    if self.time_out_counter > 1000 / self.time_out_ms:
                        cv2.imshow("Stream", self.loading_frame)
                        cv2.waitKey(1)
                    continue

                self.time_out_counter = 0
                jsonStr = self.footage_socket.recv_string()
                #print('recv_string')
                #print(jsonStr)
                jsonData = json.loads(jsonStr)
                curr_pub_time = int(jsonData['timestamp'])
                if curr_pub_time < self.min_timestamp:
                    print(f'the timestamp of the pub is too much earlier than expected.')
                    time.sleep(1)
                    continue
                #print(curr_pub_time)
                curr_sub_time = round(time.time() * 1e3)
                curr_pub_sub_diff = curr_sub_time - curr_pub_time
                #print(jsonData['timestamp'])
                if not self.last_pub_time:
                    self.last_pub_time, self.last_sub_time = curr_pub_time, curr_sub_time
                    self.pub_sub_diff = curr_pub_sub_diff
                    self.last_frame = jsonData['frame']
                    continue

                #print(f'{self.last_pub_time}, {curr_pub_time}, {self.last_sub_time}, {curr_sub_time}, {self.pub_sub_diff}, {curr_pub_sub_diff}')
                delta_time = curr_pub_time - self.last_pub_time
                if curr_pub_sub_diff < self.pub_sub_diff:
                    if curr_pub_sub_diff < self.pub_sub_diff - delta_time * 0.5:
                        self.last_pub_time, self.last_sub_time = curr_pub_time, curr_sub_time
                        self.pub_sub_diff = curr_pub_sub_diff
                        self.last_frame = jsonData['frame']
                        continue
                    print(f'{self.pub_sub_diff}, {curr_pub_sub_diff}')
                    self.last_pub_time, self.last_sub_time = curr_pub_time, curr_sub_time
                    self.pub_sub_diff = curr_pub_sub_diff
                    self.pub_sub_diff_stable = 0
                else:
                    self.pub_sub_diff_stable += 1

                if self.pub_sub_diff_stable < self.stable_threshold:
                    #cv2.imshow("Stream", string_to_image(self.last_frame))
                    #print('last frame')
                    pass
                else:
                    cv2.imshow("Stream", string_to_image(jsonData['frame']))
                    #print('curr frame')
                #self.current_frame = string_to_image(jsonData['frame'])

                if display:
                    #cv2.imshow("Stream", self.current_frame)
                    cv2.waitKey(1)

                self.last_pub_time, self.last_sub_time = curr_pub_time, curr_sub_time
                self.last_frame = jsonData['frame']
            
            except KeyboardInterrupt:
                cv2.destroyAllWindows()
                break
            except e:
                print(e)
                break
        print("Streaming Stopped!")

    def stop(self):
        """
        Sets 'keep_running' to False to stop the running loop if running.
        :return: None
        """
        self.keep_running = False

def main():
    port = PORT

    parser = argparse.ArgumentParser()
    parser.add_argument('-p', '--port',
                        help='The port which you want the Streaming Viewer to use, default'
                             ' is ' + PORT, required=False)

    args = parser.parse_args()
    if args.port:
        port = args.port

    stream_viewer = StreamViewer(port)
    stream_viewer.receive_stream()


if __name__ == '__main__':
    main()
