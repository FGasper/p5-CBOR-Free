#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <math.h>

#define CBOR_HALF_FLOAT 0xf9
#define CBOR_FLOAT      0xfa
#define CBOR_DOUBLE     0xfb

#define CBOR_FALSE      0xf4
#define CBOR_TRUE       0xf5
#define CBOR_NULL       0xf6
#define CBOR_UNDEFINED  0xf7

#define BOOLEAN_CLASS   "Types::Serialiser::Boolean"
#define TAGGED_CLASS    "CBOR::Free::Tagged"

#define MAX_ENCODE_RECURSE 98

#define ENCODE_ALLOC_CHUNK_SIZE 1024

#define IS_LITTLE_ENDIAN (BYTEORDER == 0x1234 || BYTEORDER == 0x12345678)
#define IS_64_BIT        (BYTEORDER > 0x10000)

static const uint8_t CBOR_NULL_U8  = CBOR_NULL;
static const uint8_t CBOR_FALSE_U8 = CBOR_FALSE;
static const uint8_t CBOR_TRUE_U8  = CBOR_TRUE;

enum CBOR_TYPE {
    CBOR_TYPE_UINT,
    CBOR_TYPE_NEGINT,
    CBOR_TYPE_BINARY,
    CBOR_TYPE_UTF8,
    CBOR_TYPE_ARRAY,
    CBOR_TYPE_MAP,
    CBOR_TYPE_TAG,
    CBOR_TYPE_OTHER,
};

static HV *boolean_stash;
static HV *tagged_stash;

//----------------------------------------------------------------------
// Definitions

typedef struct {
    char *buffer;
    STRLEN buflen;
    STRLEN len;
    uint8_t recurse_count;
    uint8_t scratch[9];
    bool is_canonical;
} encode_ctx;

typedef struct {
    char* start;
    STRLEN size;
    char* curbyte;
    char* end;

    union {
        uint8_t bytes[30];  // used for num -> key conversions
        float as_float;
        double as_double;
    } scratch;
} decode_ctx;

enum enum_sizetype {
    //tiny = 0,
    small = 1,
    medium = 2,
    large = 4,
    huge = 8,
    indefinite = 255,
};

union anyint {
    uint8_t u8;
    uint16_t u16;
    uint32_t u32;
    uint64_t u64;
};

typedef struct {
    enum enum_sizetype sizetype;
    union anyint size;
} struct_sizeparse;

union control_byte {
    uint8_t u8;

    struct {
        unsigned int length_type : 5;
        unsigned int major_type : 3;
    } pieces;
};

//----------------------------------------------------------------------
// Prototypes
// TODO: Be C99-compliant.

SV *_decode( pTHX_ decode_ctx* decstate );

//----------------------------------------------------------------------

void _void_uint_to_str(STRLEN num, char *numstr, const char strlen) {
    my_snprintf(numstr, strlen, "%lu", num);
}

#define _croak croak

void _die( pTHX_ I32 flags, char **argv ) {
    call_argv( "CBOR::Free::_die", G_EVAL | flags, argv );

    _croak(NULL);
}

void _croak_unrecognized(pTHX_ SV *value) {
    char * words[3] = { "Unrecognized", SvPV_nolen(value), NULL };

    _die( aTHX_ G_DISCARD, words );
}

void _croak_incomplete( pTHX_ STRLEN lack ) {
    char lackstr[24];
    _void_uint_to_str( lack, lackstr, 24 );

    char * words[3] = { "Incomplete", lackstr, NULL };

    _die( aTHX_ G_DISCARD, words );
}

void _croak_invalid_control( pTHX_ decode_ctx* decstate ) {
    const uint8_t ord = (uint8_t) *(decstate->curbyte);
    STRLEN offset = decstate->curbyte - decstate->start;

    char ordstr[24];
    char offsetstr[24];

    _void_uint_to_str(ord, ordstr, 24);
    _void_uint_to_str(offset, offsetstr, 24);

    char * words[] = { "InvalidControl", ordstr, offsetstr, NULL };

    _die( aTHX_ G_DISCARD, words );
}

void _croak_invalid_utf8( pTHX_ char *string ) {
    char * words[3] = { "InvalidUTF8", string, NULL };

    _die( aTHX_ G_DISCARD, words);
}

void _croak_invalid_map_key( pTHX_ const uint8_t byte, STRLEN offset ) {
    char bytebuf[5];

    char *bytestr;

    switch (byte) {
        case CBOR_FALSE:
            bytestr = "false";
            break;
        case CBOR_TRUE:
            bytestr = "true";
            break;
        case CBOR_NULL:
            bytestr = "null";
            break;
        case CBOR_UNDEFINED:
            bytestr = "undefined";
            break;
        default:
            switch ((byte & 0xe0) >> 5) {
                case CBOR_TYPE_ARRAY:
                    bytestr = "array";
                    break;
                case CBOR_TYPE_MAP:
                    bytestr = "map";
                    break;
                default:
                    my_snprintf( bytebuf, 5, "0x%02x", byte );
                    bytestr = bytebuf;
            }
    }

    char offsetstr[20];
    my_snprintf( offsetstr, 20, "%lu", offset );

    char * words[] = { "InvalidMapKey", bytestr, offsetstr, NULL };

    _die( aTHX_ G_DISCARD, words);
}

void _croak_cannot_decode_64bit( pTHX_ const uint8_t *u64bytes, STRLEN offset ) {
    char numhex[20];
    numhex[19] = 0;

    my_snprintf( numhex, 20, "%02x%02x_%02x%02x_%02x%02x_%02x%02x", u64bytes[0], u64bytes[1], u64bytes[2], u64bytes[3], u64bytes[4], u64bytes[5], u64bytes[6], u64bytes[7] );

    char offsetstr[20];
    my_snprintf( offsetstr, 20, "%lu", offset );

    char * words[] = { "CannotDecode64Bit", numhex, offsetstr, NULL };

    _die( aTHX_ G_DISCARD, words );
}

void _croak_cannot_decode_negative( pTHX_ UV abs, STRLEN offset ) {
    char absstr[40];
    my_snprintf(absstr, 40, sizeof(abs) == 4 ? "%lu" : "%llu", abs);

    char offsetstr[20];
    my_snprintf( offsetstr, 20, "%lu", offset );

    char * words[] = { "NegativeIntTooLow", absstr, offsetstr, NULL };

    _die( aTHX_ G_DISCARD, words );
}

#define _DECODE_CHECK_FOR_OVERAGE( decstate, len) \
    if ((len + decstate->curbyte) > decstate->end) { \
        _croak_incomplete( aTHX_ (len + decstate->curbyte) - decstate->end ); \
    }


//----------------------------------------------------------------------

static inline void _COPY_INTO_ENCODE( encode_ctx *encode_state, void *hdr, STRLEN len) {
    if ( (len + encode_state->len) > encode_state->buflen ) {
        Renew( encode_state->buffer, encode_state->buflen + len + ENCODE_ALLOC_CHUNK_SIZE, char );
        encode_state->buflen += len + ENCODE_ALLOC_CHUNK_SIZE;
    }

    Copy( hdr, encode_state->buffer + encode_state->len, len, char );
    encode_state->len += len;
}

//----------------------------------------------------------------------

// These encode num as big-endian into buffer.
// Importantly, on big-endian systems this is just a memcpy,
// while on little-endian systems it’s a bswap.

static inline void _u16_to_buffer( UV num, uint8_t *buffer ) {
    buffer[0] = num >> 8;
    buffer[1] = num;
}

static inline void _u32_to_buffer( UV num, unsigned char *buffer ) {
    buffer[0] = num >> 24;
    buffer[1] = num >> 16;
    buffer[2] = num >> 8;
    buffer[3] = num;
}

static inline void _u64_to_buffer( UV num, unsigned char *buffer ) {
    buffer[0] = num >> 56;
    buffer[1] = num >> 48;
    buffer[2] = num >> 40;
    buffer[3] = num >> 32;
    buffer[4] = num >> 24;
    buffer[5] = num >> 16;
    buffer[6] = num >> 8;
    buffer[7] = num;
}

//----------------------------------------------------------------------

// NOTE: Contrary to what we’d ordinarily expect, for canonical CBOR
// keys are only byte-sorted if their lengths are identical. Thus,
// “z” sorts EARLIER than “aa”. (cf. section 3.9 of the RFC)
I32 sortstring( pTHX_ SV *a, SV *b ) {
    return (SvCUR(a) < SvCUR(b)) ? -1 : (SvCUR(a) > SvCUR(b)) ? 1 : memcmp( SvPV_nolen(a), SvPV_nolen(b), SvCUR(a) );
}

//----------------------------------------------------------------------

// TODO? This could be a macro … it’d just be kind of unwieldy as such.
static inline void _init_length_buffer( pTHX_ UV num, enum CBOR_TYPE major_type, encode_ctx *encode_state ) {
    union control_byte *scratch0 = encode_state->scratch;
    scratch0->pieces.major_type = major_type;

    if ( num < 0x18 ) {
        scratch0->pieces.length_type = (uint8_t) num;

        _COPY_INTO_ENCODE(encode_state, encode_state->scratch, 1);
    }
    else if ( num <= 0xff ) {
        scratch0->pieces.length_type = 0x18;
        encode_state->scratch[1] = (uint8_t) num;

        _COPY_INTO_ENCODE(encode_state, encode_state->scratch, 2);
    }
    else if ( num <= 0xffff ) {
        scratch0->pieces.length_type = 0x19;

        _u16_to_buffer( num, 1 + encode_state->scratch );

        _COPY_INTO_ENCODE(encode_state, encode_state->scratch, 3);
    }
    else if ( num <= 0xffffffff ) {
        scratch0->pieces.length_type = 0x1a;

        _u32_to_buffer( num, 1 + encode_state->scratch );

        _COPY_INTO_ENCODE(encode_state, encode_state->scratch, 5);
    }
    else {
        scratch0->pieces.length_type = 0x1b;

        _u64_to_buffer( num, 1 + encode_state->scratch );

        _COPY_INTO_ENCODE(encode_state, encode_state->scratch, 9);
    }
}

void _encode( pTHX_ SV *value, encode_ctx *encode_state ) {
    ++encode_state->recurse_count;

    if (encode_state->recurse_count > MAX_ENCODE_RECURSE) {

        // call_pv() killed the process in Win32; this seems to fix that.
        static char * words[] = { NULL };
        call_argv("CBOR::Free::_die_recursion", G_EVAL|G_DISCARD, words);

        _croak(NULL);
    }

    if (!SvROK(value)) {

        if (SvIOK(value)) {
            IV val = SvIVX(value);

            // In testing, Perl’s (0 + ~0) evaluated as < 0 here,
            // but the SvUOK() check fixes that.
            if (val < 0 && !SvUOK(value)) {
                _init_length_buffer( aTHX_ -(++val), CBOR_TYPE_NEGINT, encode_state );
            }
            else {
                // NB: SvUOK doesn’t work to identify nonnegatives … ?
                _init_length_buffer( aTHX_ val, CBOR_TYPE_UINT, encode_state );
            }
        }
        else if (SvNOK(value)) {

            // Typecast to a double to accommodate long-double perls.
            double val = (double) SvNVX(value);

            char *valptr = (char *) &val;

#if IS_LITTLE_ENDIAN
            encode_state->scratch[0] = CBOR_DOUBLE;
            encode_state->scratch[1] = valptr[7];
            encode_state->scratch[2] = valptr[6];
            encode_state->scratch[3] = valptr[5];
            encode_state->scratch[4] = valptr[4];
            encode_state->scratch[5] = valptr[3];
            encode_state->scratch[6] = valptr[2];
            encode_state->scratch[7] = valptr[1];
            encode_state->scratch[8] = valptr[0];

            _COPY_INTO_ENCODE(encode_state, encode_state->scratch, 9);
#else
            char bytes[9] = { CBOR_DOUBLE, valptr[0], valptr[1], valptr[2], valptr[3], valptr[4], valptr[5], valptr[6], valptr[7] };
            _COPY_INTO_ENCODE(encode_state, bytes, 9);
#endif
        }
        else if (!SvOK(value)) {
            _COPY_INTO_ENCODE(encode_state, &CBOR_NULL_U8, 1);
        }
        else {
            char *val = SvPOK(value) ? SvPVX(value) : SvPV_nolen(value);

            STRLEN len = SvCUR(value);

            bool encode_as_text = !!SvUTF8(value);

            /*
            if (!encode_as_text) {
                STRLEN i;
                for (i=0; i<len; i++) {
                    if (val[i] & 0x80) break;
                }

                // Encode as text if there were no high-bit octets.
                encode_as_text = (i == len);
            }
            */

            _init_length_buffer( aTHX_
                len,
                (encode_as_text ? CBOR_TYPE_UTF8 : CBOR_TYPE_BINARY),
                encode_state
            );

            _COPY_INTO_ENCODE( encode_state, val, len );
        }
    }
    else if (sv_isobject(value)) {
        HV *stash = SvSTASH ( SvRV(value) );

        if (boolean_stash == stash) {
            _COPY_INTO_ENCODE(
                encode_state,
                SvIV_nomg(SvRV(value)) ? &CBOR_TRUE_U8 : &CBOR_FALSE_U8,
                1
            );
        }
        else if (tagged_stash == stash) {
            AV *array = (AV *)SvRV(value);
            SV **tag = av_fetch(array, 0, 0);
            IV tagnum = SvIV(*tag);

            _init_length_buffer( aTHX_ tagnum, CBOR_TYPE_TAG, encode_state );
            _encode( aTHX_ *(av_fetch(array, 1, 0)), encode_state );
        }

        // TODO: Support TO_JSON() method?

        else _croak_unrecognized(aTHX_ value);
    }
    else if (SVt_PVAV == SvTYPE(SvRV(value))) {
        AV *array = (AV *)SvRV(value);
        SSize_t len;
        len = 1 + av_len(array);

        _init_length_buffer( aTHX_ len, CBOR_TYPE_ARRAY, encode_state );

        SSize_t i;

        SV **cur;
        for (i=0; i<len; i++) {
            cur = av_fetch(array, i, 0);
            _encode( aTHX_ *cur, encode_state );
        }
    }
    else if (SVt_PVHV == SvTYPE(SvRV(value))) {
        HV *hash = (HV *)SvRV(value);

        char *key;
        I32 key_length;
        SV *cur;

        I32 keyscount = hv_iterinit(hash);

        _init_length_buffer( aTHX_ keyscount, CBOR_TYPE_MAP, encode_state );

        if (encode_state->is_canonical) {
            SV *keys[keyscount];

            I32 curkey = 0;

            while (hv_iternextsv(hash, &key, &key_length)) {
                keys[curkey] = newSVpvn(key, key_length);
                ++curkey;
            }

            sortsv(keys, keyscount, sortstring);

            for (curkey=0; curkey < keyscount; ++curkey) {
                cur = keys[curkey];
                key = SvPV_nolen(cur);
                key_length = SvCUR(cur);

                // Store the key.
                _init_length_buffer( aTHX_ key_length, CBOR_TYPE_BINARY, encode_state );
                _COPY_INTO_ENCODE( encode_state, key, key_length );

                cur = *( hv_fetch(hash, key, key_length, 0) );

                _encode( aTHX_ cur, encode_state );
            }
        }
        else {
            while ((cur = hv_iternextsv(hash, &key, &key_length))) {

                // Store the key.
                _init_length_buffer( aTHX_ key_length, CBOR_TYPE_BINARY, encode_state );

                _COPY_INTO_ENCODE( encode_state, key, key_length );

                _encode( aTHX_ cur, encode_state );
            }
        }
    }
    else {
        _croak_unrecognized(aTHX_ value);
    }

    --encode_state->recurse_count;
}

//----------------------------------------------------------------------
// DECODER:
//----------------------------------------------------------------------

// NB: We already checked that curbyte is safe to read!
// TODO: Just return a UV; the caller can already use control_byte
// to have parsed the size type.
struct_sizeparse _parse_for_uint_len( pTHX_ decode_ctx* decstate ) {
    struct_sizeparse ret;

    switch (*(decstate->curbyte) & 0x1f) {  // 0x1f == 0b00011111
        case 0x18:

            _DECODE_CHECK_FOR_OVERAGE( decstate, 2);

            ++decstate->curbyte;

            ret.sizetype = small;
            ret.size.u8 = *decstate->curbyte;

            ++decstate->curbyte;

            break;

        case 0x19:
            _DECODE_CHECK_FOR_OVERAGE( decstate, 3);

            ++decstate->curbyte;

            ret.sizetype = medium;
            _u16_to_buffer( *((uint16_t *) decstate->curbyte), (uint8_t *) &(ret.size.u16) );

            decstate->curbyte += 2;

            break;

        case 0x1a:
            _DECODE_CHECK_FOR_OVERAGE( decstate, 5);

            ++decstate->curbyte;

            ret.sizetype = large;
            _u32_to_buffer( *((uint32_t *) decstate->curbyte), (uint8_t *) &(ret.size.u32) );

            decstate->curbyte += 4;

            break;

        case 0x1b:
            _DECODE_CHECK_FOR_OVERAGE( decstate, 9);

            ++decstate->curbyte;

#if IS_64_BIT
            ret.sizetype = huge;
            _u64_to_buffer( *((uint64_t *) decstate->curbyte), (uint8_t *) &(ret.size.u64) );
#else
            if (!decstate->curbyte[0] && !decstate->curbyte[1] && !decstate->curbyte[2] && !decstate->curbyte[3]) {
                ret.sizetype = large;
                _u32_to_buffer( *((uint32_t *) (4 + decstate->curbyte)), (uint8_t *) &(ret.size.u32) );
            }
            else {
                _croak_cannot_decode_64bit( aTHX_ (const uint8_t *) decstate->curbyte, decstate->curbyte - decstate->start );
            }
#endif

            decstate->curbyte += 8;

            break;

        case 0x1c:
        case 0x1d:
        case 0x1e:
            _croak_invalid_control( aTHX_ decstate );
            break;

        case 0x1f:
            // ++decstate->curbyte;
            // NOTE: We do NOT increment the pointer here
            // because callers need to distinguish for themselves
            // whether indefinite is a valid case.

            ret.sizetype = indefinite;

            break;

        default:
            ret.sizetype = small;
            ret.size.u8 = (uint8_t) (*(decstate->curbyte) & 0x1f);

            decstate->curbyte++;

            break;
    }

    return ret;
}

//----------------------------------------------------------------------

SV *_decode_array( pTHX_ decode_ctx* decstate ) {
    SSize_t array_length;

    AV *array = NULL;
    SV *cur = NULL;

    struct_sizeparse sizeparse = _parse_for_uint_len( aTHX_ decstate );

    switch (sizeparse.sizetype) {
        //case tiny:
        case small:
            array_length = sizeparse.size.u8;
            break;

        case medium:
            array_length = sizeparse.size.u16;
            break;

        case large:
            array_length = sizeparse.size.u32;
            break;

        case huge:
            array_length = sizeparse.size.u64;
            break;

        case indefinite:
            ++decstate->curbyte;

            array = newAV();

            while (*(decstate->curbyte) != '\xff') {

                cur = _decode( aTHX_ decstate );
                av_push(array, cur);
                //sv_2mortal(cur);
            }

            _DECODE_CHECK_FOR_OVERAGE( decstate, 1 );

            ++decstate->curbyte;
    }

    if (!array) {
        array = newAV();

        if (array_length) {
            av_fill(array, array_length - 1);

            SSize_t i;
            for (i=0; i<array_length; i++) {
                cur = _decode( aTHX_ decstate );

                if (!av_store(array, i, cur)) {
                    _croak("Failed to store item in array!");
                }
            }
        }
    }

    return newRV_noinc( (SV *) array);
}

//----------------------------------------------------------------------

struct numbuf {
    union {
        UV uv;
        IV iv;
    } num;

    char *buffer;
};

UV _decode_uint( pTHX_ decode_ctx* decstate ) {
    struct_sizeparse sizeparse = _parse_for_uint_len( aTHX_ decstate );

    switch (sizeparse.sizetype) {
        //case tiny:
        case small:
            return sizeparse.size.u8;

        case medium:
            return sizeparse.size.u16;

        case large:
            return sizeparse.size.u32;

        case huge:
            return sizeparse.size.u64;
    }

    _croak_invalid_control( aTHX_ decstate );
}

IV _decode_negint( pTHX_ decode_ctx* decstate ) {
    struct_sizeparse sizeparse = _parse_for_uint_len( aTHX_ decstate );

    switch (sizeparse.sizetype) {
        //case tiny:
        case small:
            return ( -1 - sizeparse.size.u8 );

        case medium:
            return ( -1 - sizeparse.size.u16 );

        case large:
#if !IS_64_BIT
            if (sizeparse.size.u32 >= 0x80000000U) {
                _croak_cannot_decode_negative( aTHX_ 1 + sizeparse.size.u32, decstate->curbyte - decstate->start - 4 );
            }
#endif

            return ( -1 - (int64_t) sizeparse.size.u32 );
            break;

        case huge:
            if (sizeparse.size.u64 >= 0x8000000000000000U) {
                _croak_cannot_decode_negative( aTHX_ 1 + sizeparse.size.u64, decstate->curbyte - decstate->start - 8 );
            }

            return ( -1 - (int64_t) sizeparse.size.u64 );
    }

    _croak_invalid_control( aTHX_ decstate );
}

struct numbuf _decode_str( pTHX_ decode_ctx* decstate ) {
    struct_sizeparse sizeparse = _parse_for_uint_len( aTHX_ decstate );

    struct numbuf ret;

    switch (sizeparse.sizetype) {
        //case tiny:
        case small:
            ret.num.uv = sizeparse.size.u8;
            break;

        case medium:
            ret.num.uv = sizeparse.size.u16;
            break;

        case large:
            ret.num.uv = sizeparse.size.u32;
            break;

        case huge:
            ret.num.uv = sizeparse.size.u64;
            break;

        case indefinite:
            ++decstate->curbyte;

            SV *tempsv = newSVpvs("");

            while (*(decstate->curbyte) != '\xff') {
                //TODO: Require the same major type.

                SV *cur = _decode( aTHX_ decstate );

                sv_catsv(tempsv, cur);
            }

            _DECODE_CHECK_FOR_OVERAGE( decstate, 1 );

            ++decstate->curbyte;

            ret.buffer = SvPV_nolen(tempsv);
            ret.num.uv = SvCUR(tempsv);

            return ret;

        default:

            // This shouldn’t happen, but just in case.
            _croak("Unknown string length descriptor!");
    }

    _DECODE_CHECK_FOR_OVERAGE( decstate, ret.num.uv );

    ret.buffer = decstate->curbyte;

    decstate->curbyte += ret.num.uv;

    return ret;
}

void _decode_to_hash( pTHX_ decode_ctx* decstate, HV *hash ) {
    _DECODE_CHECK_FOR_OVERAGE( decstate, 1 );

    union control_byte control;
    control.u8 = decstate->curbyte[0];

    struct numbuf my_key;
    my_key.buffer = NULL;

    // This is going to be a hash key, so it can’t usefully be
    // anything but a string/PV.
    STRLEN keylen;
    char *keystr;

    switch (control.pieces.major_type) {
        case CBOR_TYPE_UINT:
            my_key.num.uv = _decode_uint( aTHX_ decstate );

            keystr = decstate->scratch.bytes;
            keylen = my_snprintf(decstate->scratch.bytes, sizeof(decstate->scratch.bytes), "%llu", my_key.num.uv);

            break;

        case CBOR_TYPE_NEGINT:
            my_key.num.iv = _decode_negint( aTHX_ decstate );

            keystr = decstate->scratch.bytes;
            keylen = my_snprintf(decstate->scratch.bytes, sizeof(decstate->scratch.bytes), "%lld", my_key.num.iv);

            break;

        case CBOR_TYPE_BINARY:
        case CBOR_TYPE_UTF8:
            my_key = _decode_str( aTHX_ decstate );
            keystr = my_key.buffer;
            keylen = my_key.num.uv;
            break;

        default:
            _croak_invalid_map_key( aTHX_ decstate->curbyte[0], decstate->curbyte - decstate->start );
    }

    SV *curval = _decode( aTHX_ decstate );

    hv_store(hash, keystr, keylen, curval, 0);
}

SV *_decode_map( pTHX_ decode_ctx* decstate ) {
    SSize_t keycount = 0;

    HV *hash = newHV();

    struct_sizeparse sizeparse = _parse_for_uint_len( aTHX_ decstate );

    switch (sizeparse.sizetype) {
        //case tiny:
        case small:
            keycount = sizeparse.size.u8;
            break;

        case medium:
            keycount = sizeparse.size.u16;
            break;

        case large:
            keycount = sizeparse.size.u32;
            break;

        case huge:
            keycount = sizeparse.size.u64;
            break;

        case indefinite:
            ++decstate->curbyte;

            while (*(decstate->curbyte) != '\xff') {
                _decode_to_hash( aTHX_ decstate, hash );
            }

            _DECODE_CHECK_FOR_OVERAGE( decstate, 1 );

            ++decstate->curbyte;
    }

    if (keycount) {
        while (keycount > 0) {
            _decode_to_hash( aTHX_ decstate, hash );
            --keycount;
        }
    }

    return newRV_noinc( (SV *) hash);
}

//----------------------------------------------------------------------

// Taken from RFC 7049:
double decode_half_float(uint8_t *halfp) {
    int half = (halfp[0] << 8) + halfp[1];
    int exp = (half >> 10) & 0x1f;
    int mant = half & 0x3ff;
    double val;
    if (exp == 0) val = ldexp(mant, -24);
    else if (exp != 31) val = ldexp(mant + 1024, exp - 25);
    else val = mant == 0 ? INFINITY : NAN;
    return half & 0x8000 ? -val : val;
}

static inline float _decode_float_to_le( decode_ctx* decstate, uint8_t *ptr ) {
    decstate->scratch.bytes[0] = ptr[3];
    decstate->scratch.bytes[1] = ptr[2];
    decstate->scratch.bytes[2] = ptr[1];
    decstate->scratch.bytes[3] = ptr[0];

    return decstate->scratch.as_float;
}

static inline double _decode_double_to_le( decode_ctx* decstate, uint8_t *ptr ) {
    decstate->scratch.bytes[0] = ptr[7];
    decstate->scratch.bytes[1] = ptr[6];
    decstate->scratch.bytes[2] = ptr[5];
    decstate->scratch.bytes[3] = ptr[4];
    decstate->scratch.bytes[4] = ptr[3];
    decstate->scratch.bytes[5] = ptr[2];
    decstate->scratch.bytes[6] = ptr[1];
    decstate->scratch.bytes[7] = ptr[0];

    return decstate->scratch.as_double;
}

//----------------------------------------------------------------------

SV *_decode_str_to_sv( pTHX_ decode_ctx* decstate ) {
    struct numbuf decoded_str = _decode_str( aTHX_ decstate );

    return newSVpvn( decoded_str.buffer, decoded_str.num.uv );
}

SV *_decode( pTHX_ decode_ctx* decstate ) {
    SV *ret = NULL;

    _DECODE_CHECK_FOR_OVERAGE( decstate, 1);

    struct_sizeparse sizeparse;

    union control_byte *control = (union control_byte *) decstate->curbyte;

	switch (control->pieces.major_type) {
        case CBOR_TYPE_UINT:
            ret = newSVuv( _decode_uint( aTHX_ decstate ) );

            break;
        case CBOR_TYPE_NEGINT:
            ret = newSViv( _decode_negint( aTHX_ decstate ) );

            break;
        case CBOR_TYPE_BINARY:
        case CBOR_TYPE_UTF8:
            ret = _decode_str_to_sv( aTHX_ decstate );

            // XXX: “perldoc perlapi” says this function is experimental.
            // Its use here is a calculated risk; the alternatives are
            // to invoke utf8::decode() via call_pv(), which is ugly,
            // or just to assume the UTF-8 is valid, which is wrong.
            //
            if (CBOR_TYPE_UTF8 == control->pieces.major_type) {
                if ( !sv_utf8_decode(ret) ) {
                    _croak_invalid_utf8( aTHX_ SvPV_nolen(ret) );
                }
            }

            break;
        case CBOR_TYPE_ARRAY:
            ret = _decode_array( aTHX_ decstate );

            break;
        case CBOR_TYPE_MAP:
            ret = _decode_map( aTHX_ decstate );

            break;
        case CBOR_TYPE_TAG:

            // For now, just throw this tag value away.
            sizeparse = _parse_for_uint_len( aTHX_ decstate );
            if (sizeparse.sizetype == indefinite) {
                _croak_invalid_control( aTHX_ decstate );
            }

            ret = _decode( aTHX_ decstate );

            break;
        case CBOR_TYPE_OTHER:
            switch (control->u8) {
                case CBOR_FALSE:
                    ret = newSVsv( get_sv("CBOR::Free::false", 0) );
                    ++decstate->curbyte;
                    break;

                case CBOR_TRUE:
                    ret = newSVsv( get_sv("CBOR::Free::true", 0) );
                    ++decstate->curbyte;
                    break;

                case CBOR_NULL:
                case CBOR_UNDEFINED:
                    ret = newSVsv( &PL_sv_undef );
                    ++decstate->curbyte;
                    break;

                case CBOR_HALF_FLOAT:
                    _DECODE_CHECK_FOR_OVERAGE( decstate, 3 );

                    ret = newSVnv( decode_half_float( (uint8_t *) (1 + decstate->curbyte) ) );

                    decstate->curbyte += 3;
                    break;

                case CBOR_FLOAT:
                    _DECODE_CHECK_FOR_OVERAGE( decstate, 5 );

                    float decoded_flt;

#if IS_LITTLE_ENDIAN
                    decoded_flt = _decode_float_to_le( decstate, (uint8_t *) (1 + decstate->curbyte ) );
#else
                    decoded_flt = *( (float *) (1 + decstate->curbyte) );
#endif

                    ret = newSVnv( (NV) decoded_flt );

                    decstate->curbyte += 5;
                    break;

                case CBOR_DOUBLE:
                    _DECODE_CHECK_FOR_OVERAGE( decstate, 9 );

                    double decoded_dbl;

#if IS_LITTLE_ENDIAN
                    decoded_dbl = _decode_double_to_le( decstate, (uint8_t *) (1 + decstate->curbyte ) );
#else
                    decoded_dbl = *( (double *) (1 + decstate->curbyte) );
#endif

                    ret = newSVnv( (NV) decoded_dbl );

                    decstate->curbyte += 9;
                    break;

                default:
                    _croak_invalid_control( aTHX_ decstate );
            }

            break;

        default:
            _croak("Unknown type!");
    }

    return ret;
}

//----------------------------------------------------------------------

MODULE = CBOR::Free           PACKAGE = CBOR::Free

PROTOTYPES: DISABLE

BOOT:
    HV *stash = gv_stashpv("CBOR::Free", FALSE);
    newCONSTSUB(stash, "_MAX_RECURSION", newSVuv( MAX_ENCODE_RECURSE ));

    boolean_stash = gv_stashpv(BOOLEAN_CLASS, 1);
    tagged_stash = gv_stashpv(TAGGED_CLASS, 1);

SV *
encode( SV * value, ... )
    CODE:
        encode_ctx encode_state;

        encode_state.buffer = NULL;
        Newx( encode_state.buffer, ENCODE_ALLOC_CHUNK_SIZE, char );

        encode_state.buflen = ENCODE_ALLOC_CHUNK_SIZE;
        encode_state.len = 0;
        encode_state.recurse_count = 0;

        encode_state.is_canonical = false;

        U8 i;
        for (i=1; i<items; i++) {
            if (!(i % 2)) break;

            if ((SvCUR(ST(i)) == 9) && !memcmp( SvPV_nolen(ST(i)), "canonical", 9)) {
                ++i;
                if (i<items) encode_state.is_canonical = SvTRUE(ST(i));
                break;
            }
        }

        _encode(aTHX_ value, &encode_state);

        // Don’t use newSVpvn here because that will copy the string.
        // Instead, create a new SV and manually assign its pieces.
        // This follows the example from ext/POSIX/POSIX.xs:

        // Ensure there’s a trailing NUL:
        _COPY_INTO_ENCODE( &encode_state, "\0", 1 );

        // Resize (down) to avoid memory leakage.
        Renew( encode_state.buffer, encode_state.len, char );

        RETVAL = newSV(0);
        SvUPGRADE(RETVAL, SVt_PV);
        SvPV_set(RETVAL, encode_state.buffer);
        SvPOK_on(RETVAL);
        SvCUR_set(RETVAL, encode_state.len - 1);
        SvLEN_set(RETVAL, encode_state.len);

        //Safefree(encode_state.buffer);
    OUTPUT:
        RETVAL


SV *
decode( SV *cbor )
    CODE:
        char *cborstr;
        STRLEN cborlen;

        cborstr = SvPV(cbor, cborlen);

        decode_ctx decode_state = {
            cborstr,
            cborlen,
            cborstr,
            cborstr + cborlen,
            false,
        };

        RETVAL = _decode( aTHX_ &decode_state );

        if (decode_state.curbyte != decode_state.end) {
            STRLEN bytes_count = decode_state.end - decode_state.curbyte;

            char numstr[24];
            _void_uint_to_str(bytes_count, numstr, 24);

            char * words[2] = { numstr, NULL };

            call_argv("CBOR::Free::_warn_decode_leftover", G_DISCARD, words);
        }

    OUTPUT:
        RETVAL
