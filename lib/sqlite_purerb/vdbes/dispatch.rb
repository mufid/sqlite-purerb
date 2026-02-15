# frozen_string_literal: true

module SqlitePurerb
  module Vdbes
    DISPATCH = Array.new(256)

    # Program control
    DISPATCH[VDBE::OP::INIT]           = Read::OpInit
    DISPATCH[VDBE::OP::HALT]           = Read::OpHalt
    DISPATCH[VDBE::OP::GOTO]           = Read::OpGoto
    DISPATCH[VDBE::OP::TRANSACTION]    = Read::OpTransaction

    # Cursor operations
    DISPATCH[VDBE::OP::OPEN_READ]      = Read::OpOpenRead
    DISPATCH[VDBE::OP::REWIND]         = Read::OpRewind
    DISPATCH[VDBE::OP::NEXT]           = Read::OpNext
    DISPATCH[VDBE::OP::CLOSE]          = Read::OpClose

    # Column and register operations
    DISPATCH[VDBE::OP::COLUMN]         = Read::OpColumn
    DISPATCH[VDBE::OP::ROWID]          = Read::OpRowid
    DISPATCH[VDBE::OP::RESULT_ROW]     = Read::OpResultRow

    # Load values into registers
    DISPATCH[VDBE::OP::INTEGER]        = Read::OpInteger
    DISPATCH[VDBE::OP::STRING8]        = Read::OpString8
    DISPATCH[VDBE::OP::NULL]           = Read::OpNull
    DISPATCH[VDBE::OP::COPY]           = Read::OpCopy

    # Type affinity
    DISPATCH[VDBE::OP::REAL_AFFINITY]  = Read::OpRealAffinity

    # Comparison operations
    DISPATCH[VDBE::OP::EQ]             = Read::OpEq
    DISPATCH[VDBE::OP::NE]             = Read::OpNe
    DISPATCH[VDBE::OP::LT]             = Read::OpLt
    DISPATCH[VDBE::OP::LE]             = Read::OpLe
    DISPATCH[VDBE::OP::GT]             = Read::OpGt
    DISPATCH[VDBE::OP::GE]             = Read::OpGe

    # Logical operations
    DISPATCH[VDBE::OP::IF]             = Read::OpIf
    DISPATCH[VDBE::OP::IF_NOT]         = Read::OpIfNot
    DISPATCH[VDBE::OP::AND]            = Read::OpAnd
    DISPATCH[VDBE::OP::OR]             = Read::OpOr
    DISPATCH[VDBE::OP::NOT]            = Read::OpNot
    DISPATCH[VDBE::OP::IS_NULL]        = Read::OpIsNull
    DISPATCH[VDBE::OP::NOT_NULL]       = Read::OpNotNull
    DISPATCH[VDBE::OP::NOOP]          = Read::OpNoop

    # Sorter operations (ORDER BY)
    DISPATCH[VDBE::OP::SORTER_OPEN]    = Read::OpSorterOpen
    DISPATCH[VDBE::OP::MAKE_RECORD]    = Read::OpMakeRecord
    DISPATCH[VDBE::OP::SORTER_INSERT]  = Read::OpSorterInsert
    DISPATCH[VDBE::OP::OPEN_PSEUDO]    = Read::OpOpenPseudo
    DISPATCH[VDBE::OP::SORTER_SORT]    = Read::OpSorterSort
    DISPATCH[VDBE::OP::SORTER_DATA]    = Read::OpSorterData
    DISPATCH[VDBE::OP::SORTER_NEXT]    = Read::OpSorterNext

    # Limit/Offset operations
    DISPATCH[VDBE::OP::DECR_JUMP_ZERO] = Read::OpDecrJumpZero
    DISPATCH[VDBE::OP::MUST_BE_INT]    = Read::OpMustBeInt
    DISPATCH[VDBE::OP::OFFSET_LIMIT]   = Read::OpOffsetLimit
    DISPATCH[VDBE::OP::IF_POS]         = Read::OpIfPos

    # Ephemeral table operations (ORDER BY + LIMIT)
    DISPATCH[VDBE::OP::OPEN_EPHEMERAL] = Read::OpOpenEphemeral
    DISPATCH[VDBE::OP::SEQUENCE]       = Read::OpSequence
    DISPATCH[VDBE::OP::IF_NOT_ZERO]    = Read::OpIfNotZero
    DISPATCH[VDBE::OP::LAST]           = Read::OpLast
    DISPATCH[VDBE::OP::IDX_LE]         = Read::OpIdxLE
    DISPATCH[VDBE::OP::DELETE]         = Read::OpDelete
    DISPATCH[VDBE::OP::SORT]           = Read::OpSort
    DISPATCH[VDBE::OP::IDX_INSERT]     = Read::OpIdxInsert

    # Index scan operations
    DISPATCH[VDBE::OP::SEEK_GE]        = Read::OpSeekGE
    DISPATCH[VDBE::OP::IDX_GT]         = Read::OpIdxGT
    DISPATCH[VDBE::OP::DEFERRED_SEEK]  = Read::OpDeferredSeek
    DISPATCH[VDBE::OP::IDX_ROWID]      = Read::OpIdxRowid

    DISPATCH.freeze
  end
end
