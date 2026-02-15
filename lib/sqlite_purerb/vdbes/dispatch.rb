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

    DISPATCH.freeze
  end
end
