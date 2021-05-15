# cython: language_level=3
#
# This is free and unencumbered software released into the public domain.
#
#     https://unlicense.org
#
# SPDX-License-Identifier: Unlicense
#
# Contributors:
#     Kristoffer Paulsson - initial implementation
#
"""Implementation of AIFF 1.3 (not fully.)"""
import struct
import sys
from contextlib import contextmanager

ctypedef unsigned char[4] ID;
ctypedef unsigned char[4] os_type;

ctypedef struct Chunk:
    ID ck_id;
    long ck_size;
    ID form_type;
    char *chunks;

ID_FORM = b"FORM"
ID_TYPE = b"AIFF"


ctypedef struct CommonChunk:
    ID ck_id;
    long ck_size;
    short num_channels;
    unsigned long num_sample_frames;
    short sample_size;
    long double sample_rate;

ID_COMMON = b"COMM"


ctypedef struct SoundDataChunk:
    ID ck_id;
    long ck_size;
    unsigned long offset;
    unsigned long block_size;
    unsigned char *sound_data;

ID_SOUND_DATA = b"SSND"


ctypedef short marker_id;

ctypedef struct Marker:
    marker_id id;
    unsigned long position;
    unsigned char *marker_name;  # Pascal string

ctypedef struct MarkerChunk:
    ID ck_id;
    long ck_size;
    unsigned short num_markers;
    Marker *markers;

ID_MARKER = b"MARK"


ctypedef enum Looping:
    loopNo = 0
    loopForward = 1
    loopForwardBackward = 2

ctypedef struct Loop:
    short play_mode;
    marker_id begin_loop;
    marker_id end_loop;

ctypedef struct InstrumentChunk:
    ID ck_id;
    long ck_size;
    char base_note;
    char detune;
    char low_note;
    char high_note;
    char low_velocity;
    char high_velocity;
    short gain;
    Loop sustain_loop;
    Loop release_loop;

ID_INSTRUMENT = b"INST"


ctypedef struct MIDIDataChunk:
    ID ck_id;
    long ck_size;
    unsigned char *midi_data;

ID_MIDI_DATA = b"MIDI"


ctypedef struct AudioRecordingChunk:
    ID ck_id;
    long ck_size;
    unsigned char aes_channel_status_data[24];

ID_AUDIO_RECORDING = b"AESD"


ctypedef struct ApplicationSpecificChunk:
    ID ck_id;
    long ck_size;
    os_type application_signature;
    char *data;

ID_APPLICATION_SPECIFIC = b"APPL"


ctypedef struct Comment:
    unsigned long time_stamp;
    marker_id marker;
    unsigned short count;
    char *text;

ctypedef struct CommentsChunk:
    id ck_id;
    long ck_size;
    unsigned short num_comments;
    Comment *comments;

ID_COMMENT = b"COMT"


ctypedef struct TextChunk:
    ID ck_id;
    long ck_size;
    char *text;

ID_NAME = b"NAME"
ID_AUTHOR = b"AUTH"
ID_COPYRIGHT = b"(c) "
ID_ANNOTATION = b"ANNO"


STANDARD_FORMAT = struct.Struct("4Bl4B4BlhLhdxx4BlLL")

STANDARD_FORMAT.pack(
    ID_FORM, 80+x, ID_TYPE,
    ID_COMMON, 18, num_channels, num_sample_frames, sample_size, sample_rate,
    ID_SOUND_DATA, 8+x, 0, 0)


class AudioFile:
    """Audio file with all associated data."""

    FORMAT = struct.Struct(">4Bl4B4BlhLhdxx4BlLL")
    CHANNELS = (1, 2, 3, 4, 4, 6)
    INPUTS = (
        ("mono",),
        ("left", "right"),
        ("left", "right", "center"),
        ("front_left", "front_right", "rear_left", "rear_right"),
        ("left", "center", "right", "surround"),
        ("left", "left_center", "center", "right", "right_center", "surround"),
    )

    SND_MONOPHONIC = 1
    SND_STEREO = 2
    SND_3CHANNEL = 3
    SND_QUAD = 4
    SND_4CHANNEL = 5
    SND_6CHANNEL = 6

    BITS_8 = 1
    BITS_16 = 2
    BITS_24 = 3

    RATE_DVD = 48000.0
    RATE_STUDIO = 192000.0

    def __init__(self, channel_width: int, sampling: int, sound: int):
        self._width = channel_width
        self._sound = sound-1

        self._num_channels = self.CHANNELS[self._sound]
        self._num_sample_frames = 0
        self._sample_size = sound * 8
        self._sample_rate = float(sampling)

        self._frames_cnt = 0
        self._hundred = self._sample_rate // 100
        self._size = self._hundred * self._width

        if self._hundred * 100 != self._sample_rate:
            raise ValueError("Sample rate not divisible by 100.")

    def _heading(self) -> bytes:
        return self.FORMAT.pack(
            ID_FORM, 80+x, ID_TYPE,
            ID_COMMON, 18, self._num_channels, self._num_sample_frames, self._sample_size, self._sample_rate,
            ID_SOUND_DATA, 8+x, 0, 0
        )

    @contextmanager
    @classmethod
    def record(cls, sample_rate: float, num_channels: int):
        """Record sound."""
        resource = acquire_resource(*args, **kwds)
        try:
            yield resource
        finally:
            # Code to release resource, e.g.:
            release_resource(resource)

    def hundreds(self, **channels) -> None:
        """Encode a hundred of a second."""
        for channel in self.INPUTS[self._sound]:
            if len(channels[channel]) != self._size:
                raise ValueError("Channel {} not of length {}".format(channel, self._size))

        cdef int num = len(channels), idx = 0
        cdef unsigned char * streams[6]
        cdef unsigned char *byte_array
        cdef unsigned char *buffer
        cdef bint endianness = False if sys.byteorder == "little" else True

        data = bytes(self._size * num)
        byte_array = <unsigned char *>data
        buffer = byte_array

        for channel in self.INPUTS[self._sound]:
            byte_array = <unsigned char *>channels[channel]
            streams[idx] = byte_array
            idx += 1

        with nogil:
            pass