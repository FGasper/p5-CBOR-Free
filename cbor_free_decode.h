#ifndef CBOR_FREE_DECODE
#define CBOR_FREE_DECODE

#include "cbor_free_common.h"
#include "cbor_free_boolean.h"

#define CBF_FLAG_PRESERVE_REFERENCES 1
#define CBF_FLAG_NAIVE_UTF8 2
#define CBF_FLAG_SEQUENCE_MODE 4

//----------------------------------------------------------------------
// Definitions

typedef struct {
    char* start;
    STRLEN size;
    char* curbyte;
    char* end;

    HV * tag_handler;

    void **reflist;
    UV reflistlen;

    UV flags;

    union {
        uint8_t bytes[30];  // used for num -> key conversions
        float as_float;
        double as_double;
    } scratch;

} decode_ctx;

typedef struct {
    decode_ctx* decode_state;
    SV* cbor;
} seqdecode_ctx;

struct numbuf {
    union {
        UV uv;
        IV iv;
    } num;

    char *buffer;
};

//----------------------------------------------------------------------

SV *cbf_decode( pTHX_ SV *cbor, HV *tag_handler, UV flags );

SV *cbf_decode_one( pTHX_ decode_ctx* decstate );

decode_ctx* create_decode_state( pTHX_ SV *cbor, HV *tag_handler, UV flags );
void free_decode_state( pTHX_ decode_ctx* decode_state);

void renew_decode_state_buffer( pTHX_ decode_ctx *decode_state, SV *cbor );
void advance_decode_state_buffer( pTHX_ decode_ctx *decode_state );

#endif
