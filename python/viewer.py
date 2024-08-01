import argparse

import cv2
import numpy as np
import zmq

#from utils import string_to_image
import time
import json


PORT = '5555'

def string_to_image(string):
    import numpy as np
    import cv2
    import base64
    img = base64.b64decode(string)
    npimg = np.frombuffer(img, dtype=np.uint8)
    return cv2.flip(cv2.imdecode(npimg, 1), 1)


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
        self.current_frame = None
        self.keep_running = True

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

    def receive_stream(self, display=True):
        """
        Displays displayed stream in a window if no arguments are passed.
        Keeps updating the 'current_frame' attribute with the most recent frame, this can be accessed using 'self.current_frame'
        :param display: boolean, If False no stream output will be displayed.
        :return: None
        """
        #print('what?')
        data = self.footage_socket.recv()
        print(len(data))
        #return
        self.keep_running = True
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
