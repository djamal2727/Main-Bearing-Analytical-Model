/* Symbolic values.
   Copyright (C) 2019-2020 Free Software Foundation, Inc.
   Contributed by David Malcolm <dmalcolm@redhat.com>.

This file is part of GCC.

GCC is free software; you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3, or (at your option)
any later version.

GCC is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with GCC; see the file COPYING3.  If not see
<http://www.gnu.org/licenses/>.  */

#include "config.h"
#include "system.h"
#include "coretypes.h"
#include "tree.h"
#include "diagnostic-core.h"
#include "gimple-pretty-print.h"
#include "function.h"
#include "basic-block.h"
#include "gimple.h"
#include "gimple-iterator.h"
#include "diagnostic-core.h"
#include "graphviz.h"
#include "options.h"
#include "cgraph.h"
#include "tree-dfa.h"
#include "stringpool.h"
#include "convert.h"
#include "target.h"
#include "fold-const.h"
#include "tree-pretty-print.h"
#include "tristate.h"
#include "bitmap.h"
#include "selftest.h"
#include "function.h"
#include "json.h"
#include "analyzer/analyzer.h"
#include "analyzer/analyzer-logging.h"
#include "options.h"
#include "cgraph.h"
#include "cfg.h"
#include "digraph.h"
#include "analyzer/call-string.h"
#include "analyzer/program-point.h"
#include "analyzer/store.h"
#include "analyzer/region-model.h"

#if ENABLE_ANALYZER

namespace ana {

/* struct complexity.  */

/* Get complexity for a new node that references REG
   (the complexity of REG, plus one for the new node).  */

complexity::complexity (const region *reg)
: m_num_nodes (reg->get_complexity ().m_num_nodes + 1),
  m_max_depth (reg->get_complexity ().m_max_depth + 1)
{
}

/* Get complexity for a new node that references SVAL.
   (the complexity of SVAL, plus one for the new node).  */

complexity::complexity (const svalue *sval)
: m_num_nodes (sval->get_complexity ().m_num_nodes + 1),
  m_max_depth (sval->get_complexity ().m_max_depth + 1)
{
}

/* Get complexity for a new node that references nodes with complexity
   C1 and C2.  */

complexity
complexity::from_pair (const complexity &c1, const complexity &c2)
{
  return complexity (c1.m_num_nodes + c2.m_num_nodes + 1,
		     MAX (c1.m_max_depth, c2.m_max_depth) + 1);
}

/* class svalue and its various subclasses.  */

/* class svalue.  */

/* Dump a representation of this svalue to stderr.  */

DEBUG_FUNCTION void
svalue::dump (bool simple) const
{
  pretty_printer pp;
  pp_format_decoder (&pp) = default_tree_printer;
  pp_show_color (&pp) = pp_show_color (global_dc->printer);
  pp.buffer->stream = stderr;
  dump_to_pp (&pp, simple);
  pp_newline (&pp);
  pp_flush (&pp);
}

/* Generate a textual representation of this svalue for debugging purposes.  */

label_text
svalue::get_desc (bool simple) const
{
  pretty_printer pp;
  pp_format_decoder (&pp) = default_tree_printer;
  dump_to_pp (&pp, simple);
  return label_text::take (xstrdup (pp_formatted_text (&pp)));
}

/* Return a new json::string describing the svalue.  */

json::value *
svalue::to_json () const
{
  label_text desc = get_desc (true);
  json::value *sval_js = new json::string (desc.m_buffer);
  desc.maybe_free ();
  return sval_js;
}

/* If this svalue is a constant_svalue, return the underlying tree constant.
   Otherwise return NULL_TREE.  */

tree
svalue::maybe_get_constant () const
{
  if (const constant_svalue *cst_sval = dyn_cast_constant_svalue ())
    return cst_sval->get_constant ();
  else
    return NULL_TREE;
}

/* If this svalue is a cast (i.e a unaryop NOP_EXPR or VIEW_CONVERT_EXPR),
   return the underlying svalue.
   Otherwise return NULL.  */

const svalue *
svalue::maybe_undo_cast () const
{
  if (const unaryop_svalue *unaryop_sval = dyn_cast_unaryop_svalue ())
    {
      enum tree_code op = unaryop_sval->get_op ();
      if (op == NOP_EXPR || op == VIEW_CONVERT_EXPR)
	return unaryop_sval->get_arg ();
    }
  return NULL;
}

/* If this svalue is an unmergeable decorator around another svalue, return
   the underlying svalue.
   Otherwise return this svalue.  */

const svalue *
svalue::unwrap_any_unmergeable () const
{
  if (const unmergeable_svalue *unmergeable = dyn_cast_unmergeable_svalue ())
    return unmergeable->get_arg ();
  return this;
}

/* Attempt to merge THIS with OTHER, returning the merged svalue.
   Return NULL if not mergeable.  */

const svalue *
svalue::can_merge_p (const svalue *other,
		     region_model_manager *mgr,
		     model_merger *merger) const
{
  if (!(get_type () && other->get_type ()))
    return NULL;

  if (!types_compatible_p (get_type (), other->get_type ()))
    return NULL;

  /* Reject attempts to merge unmergeable svalues.  */
  if ((get_kind () == SK_UNMERGEABLE)
      || (other->get_kind () == SK_UNMERGEABLE))
    return NULL;

  /* Reject attempts to merge NULL pointers with not-NULL-pointers.  */
  if (POINTER_TYPE_P (get_type ()))
    {
      bool null0 = false;
      bool null1 = false;
      if (tree cst0 = maybe_get_constant ())
	if (zerop (cst0))
	  null0 = true;
      if (tree cst1 = other->maybe_get_constant ())
	if (zerop (cst1))
	  null1 = true;
      if (null0 != null1)
	return NULL;
    }

  /* Widening.  */
  /* Merge: (new_cst, existing_cst) -> widen (existing, new).  */
  if (maybe_get_constant () && other->maybe_get_constant ())
    {
      return mgr->get_or_create_widening_svalue (other->get_type (),
						 merger->m_point,
						 other, this);
    }

  /* Merger of:
	 this: BINOP (X, OP, CST)
	other: X, where X is non-widening
	   to: WIDENING (other, this).  */
  if (const binop_svalue *binop_sval = dyn_cast_binop_svalue ())
    if (binop_sval->get_arg0 () == other
	&& binop_sval->get_arg1 ()->get_kind () == SK_CONSTANT
	&& other->get_kind () != SK_WIDENING)
      return mgr->get_or_create_widening_svalue (other->get_type (),
						 merger->m_point,
						 other, this);

  /* Merge: (Widen(existing_val, V), existing_val) -> Widen (existing_val, V)
     and thus get a fixed point.  */
  if (const widening_svalue *widen_sval = dyn_cast_widening_svalue ())
    {
      if (other == widen_sval->get_base_svalue ())
	return this;
      if (other == widen_sval->get_iter_svalue ())
	return this;
    }

  if (const binop_svalue *binop_sval = dyn_cast_binop_svalue ())
    if (const widening_svalue *widen_arg0
	= binop_sval->get_arg0 ()->dyn_cast_widening_svalue ())
      {
	if (other == binop_sval->get_arg1 ())
	  {
	    /* Merger of: (Widen(..., OTHER) BINOP X)
	       and      : OTHER
	       to       : (Widen(..., OTHER) BINOP X)
	       e.g. merge of Widen(0, 1) + 1 with 1 to the Widen(0, 1) + 1.  */
	    return this;
	  }

	/* Merger of : (Widen() BINOP X)
	   and       : Widen()
	   to        : Widen()
	   e.g. merge of Widen(0, 1) + 1 and Widen(0, 1) to Widen(0, 1).
	   However, we want to update constraints for this case, since we're
	   considering another iteration.
	   Presumably we also want to ensure that it converges; we don't want
	   a descending chain of constraints.  */
	if (other == widen_arg0)
	  {
	    return widen_arg0;
	  }

	/* Merger of:
	    this: BINOP(WIDENING(BASE, BINOP(BASE, X)), X)
	   other: BINOP(BASE, X)
	      to: WIDENING(BASE, BINOP(BASE, X)).  */
	if (widen_arg0->get_iter_svalue () == other)
	  if (const binop_svalue *other_binop_sval
		= other->dyn_cast_binop_svalue ())
	    if (other_binop_sval->get_arg0 () == widen_arg0->get_base_svalue ()
		&& other_binop_sval->get_arg1 () == binop_sval->get_arg1 ())
	      return widen_arg0;
      }

  return mgr->get_or_create_unknown_svalue (get_type ());
}

/* Determine if this svalue is either within LIVE_SVALUES, or is implicitly
   live with respect to LIVE_SVALUES and MODEL.  */

bool
svalue::live_p (const svalue_set &live_svalues,
		const region_model *model) const
{
  /* Determine if SVAL is explicitly live.  */
  if (const_cast<svalue_set &> (live_svalues).contains (this))
    return true;

  /* Otherwise, determine if SVAL is implicitly live due to being made of
     other live svalues.  */
  return implicitly_live_p (live_svalues, model);
}

/* Base implementation of svalue::implicitly_live_p.  */

bool
svalue::implicitly_live_p (const svalue_set &, const region_model *) const
{
  return false;
}

/* class region_svalue : public svalue.  */

/* Implementation of svalue::dump_to_pp vfunc for region_svalue.  */

void
region_svalue::dump_to_pp (pretty_printer *pp, bool simple) const
{
  if (simple)
    {
      pp_string (pp, "&");
      m_reg->dump_to_pp (pp, simple);
    }
  else
    {
      pp_string (pp, "region_svalue(");
      print_quoted_type (pp, get_type ());
      pp_string (pp, ", ");
      m_reg->dump_to_pp (pp, simple);
      pp_string (pp, ")");
    }
}

/* Implementation of svalue::accept vfunc for region_svalue.  */

void
region_svalue::accept (visitor *v) const
{
  v->visit_region_svalue (this);
  m_reg->accept (v);
}

/* Evaluate the condition LHS OP RHS.
   Subroutine of region_model::eval_condition for when we have a pair of
   pointers.  */

tristate
region_svalue::eval_condition (const region_svalue *lhs,
			       enum tree_code op,
			       const region_svalue *rhs)
{
  /* See if they point to the same region.  */
  const region *lhs_reg = lhs->get_pointee ();
  const region *rhs_reg = rhs->get_pointee ();
  bool ptr_equality = lhs_reg == rhs_reg;
  switch (op)
    {
    default:
      gcc_unreachable ();

    case EQ_EXPR:
      if (ptr_equality)
	return tristate::TS_TRUE;
      else
	return tristate::TS_FALSE;
      break;

    case NE_EXPR:
      if (ptr_equality)
	return tristate::TS_FALSE;
      else
	return tristate::TS_TRUE;
      break;

    case GE_EXPR:
    case LE_EXPR:
      if (ptr_equality)
	return tristate::TS_TRUE;
      break;

    case GT_EXPR:
    case LT_EXPR:
      if (ptr_equality)
	return tristate::TS_FALSE;
      break;
    }

  return tristate::TS_UNKNOWN;
}

/* class constant_svalue : public svalue.  */

/* Implementation of svalue::dump_to_pp vfunc for constant_svalue.  */

void
constant_svalue::dump_to_pp (pretty_printer *pp, bool simple) const
{
  if (simple)
    {
      pp_string (pp, "(");
      dump_tree (pp, get_type ());
      pp_string (pp, ")");
      dump_tree (pp, m_cst_expr);
    }
  else
    {
      pp_string (pp, "constant_svalue(");
      print_quoted_type (pp, get_type ());
      pp_string (pp, ", ");
      dump_tree (pp, m_cst_expr);
      pp_string (pp, ")");
    }
}

/* Implementation of svalue::accept vfunc for constant_svalue.  */

void
constant_svalue::accept (visitor *v) const
{
  v->visit_constant_svalue (this);
}

/* Implementation of svalue::implicitly_live_p vfunc for constant_svalue.
   Constants are implicitly live.  */

bool
constant_svalue::implicitly_live_p (const svalue_set &,
				    const region_model *) const
{
  return true;
}

/* Evaluate the condition LHS OP RHS.
   Subroutine of region_model::eval_condition for when we have a pair of
   constants.  */

tristate
constant_svalue::eval_condition (const constant_svalue *lhs,
				  enum tree_code op,
				  const constant_svalue *rhs)
{
  tree lhs_const = lhs->get_constant ();
  tree rhs_const = rhs->get_constant ();

  gcc_assert (CONSTANT_CLASS_P (lhs_const));
  gcc_assert (CONSTANT_CLASS_P (rhs_const));

  /* Check for comparable types.  */
  if (types_compatible_p (TREE_TYPE (lhs_const), TREE_TYPE (rhs_const)))
    {
      tree comparison
	= fold_binary (op, boolean_type_node, lhs_const, rhs_const);
      if (comparison == boolean_true_node)
	return tristate (tristate::TS_TRUE);
      if (comparison == boolean_false_node)
	return tristate (tristate::TS_FALSE);
    }
  return tristate::TS_UNKNOWN;
}

/* class unknown_svalue : public svalue.  */

/* Implementation of svalue::dump_to_pp vfunc for unknown_svalue.  */

void
unknown_svalue::dump_to_pp (pretty_printer *pp, bool simple) const
{
  if (simple)
    {
      pp_string (pp, "UNKNOWN(");
      if (get_type ())
	dump_tree (pp, get_type ());
      pp_character (pp, ')');
    }
  else
    {
      pp_string (pp, "unknown_svalue(");
      if (get_type ())
	dump_tree (pp, get_type ());
      pp_character (pp, ')');
    }
}

/* Implementation of svalue::accept vfunc for unknown_svalue.  */

void
unknown_svalue::accept (visitor *v) const
{
  v->visit_unknown_svalue (this);
}

/* Get a string for KIND for use in debug dumps.  */

const char *
poison_kind_to_str (enum poison_kind kind)
{
  switch (kind)
    {
    default:
      gcc_unreachable ();
    case POISON_KIND_FREED:
      return "freed";
    case POISON_KIND_POPPED_STACK:
      return "popped stack";
    }
}

/* class poisoned_svalue : public svalue.  */

/* Implementation of svalue::dump_to_pp vfunc for poisoned_svalue.  */

void
poisoned_svalue::dump_to_pp (pretty_printer *pp, bool simple) const
{
  if (simple)
    pp_printf (pp, "POISONED(%s)", poison_kind_to_str (m_kind));
  else
    pp_printf (pp, "poisoned_svalue(%s)", poison_kind_to_str (m_kind));
}

/* Implementation of svalue::accept vfunc for poisoned_svalue.  */

void
poisoned_svalue::accept (visitor *v) const
{
  v->visit_poisoned_svalue (this);
}

/* class setjmp_svalue's implementation is in engine.cc, so that it can use
   the declaration of exploded_node.  */

/* class initial_svalue : public svalue.  */

/* Implementation of svalue::dump_to_pp vfunc for initial_svalue.  */

void
initial_svalue::dump_to_pp (pretty_printer *pp, bool simple) const
{
  if (simple)
    {
      pp_string (pp, "INIT_VAL(");
      m_reg->dump_to_pp (pp, simple);
      pp_string (pp, ")");
    }
  else
    {
      pp_string (pp, "initial_svalue(");
      print_quoted_type (pp, get_type ());
      pp_string (pp, ", ");
      m_reg->dump_to_pp (pp, simple);
      pp_string (pp, ")");
    }
}

/* Implementation of svalue::accept vfunc for initial_svalue.  */

void
initial_svalue::accept (visitor *v) const
{
  v->visit_initial_svalue (this);
  m_reg->accept (v);
}

/* Implementation of svalue::implicitly_live_p vfunc for initial_svalue.  */

bool
initial_svalue::implicitly_live_p (const svalue_set &,
				   const region_model *model) const
{
  /* This svalue may be implicitly live if the region still implicitly
     has its initial value and is reachable.  */

  /* It must be a region that exists; we don't want to consider
     INIT_VAL(R) as still being implicitly reachable if R is in
     a popped stack frame.  */
  if (model->region_exists_p (m_reg))
    {
      const svalue *reg_sval = model->get_store_value (m_reg);
      if (reg_sval == this)
	return true;
    }

  return false;
}

/* class unaryop_svalue : public svalue.  */

/* Implementation of svalue::dump_to_pp vfunc for unaryop_svalue.  */

void
unaryop_svalue::dump_to_pp (pretty_printer *pp, bool simple) const
{
  if (simple)
    {
      if (m_op == VIEW_CONVERT_EXPR || m_op == NOP_EXPR)
	{
	  pp_string (pp, "CAST(");
	  dump_tree (pp, get_type ());
	  pp_string (pp, ", ");
	  m_arg->dump_to_pp (pp, simple);
	  pp_character (pp, ')');
	}
      else
	{
	  pp_character (pp, '(');
	  pp_string (pp, get_tree_code_name (m_op));
	  //pp_string (pp, op_symbol_code (m_op));
	  m_arg->dump_to_pp (pp, simple);
	  pp_character (pp, ')');
	}
    }
  else
    {
      pp_string (pp, "unaryop_svalue (");
      pp_string (pp, get_tree_code_name (m_op));
      pp_string (pp, ", ");
      m_arg->dump_to_pp (pp, simple);
      pp_character (pp, ')');
    }
}

/* Implementation of svalue::accept vfunc for unaryop_svalue.  */

void
unaryop_svalue::accept (visitor *v) const
{
  v->visit_unaryop_svalue (this);
  m_arg->accept (v);
}

/* Implementation of svalue::implicitly_live_p vfunc for unaryop_svalue.  */

bool
unaryop_svalue::implicitly_live_p (const svalue_set &live_svalues,
				   const region_model *model) const
{
  return get_arg ()->live_p (live_svalues, model);
}

/* class binop_svalue : public svalue.  */

/* Implementation of svalue::dump_to_pp vfunc for binop_svalue.  */

void
binop_svalue::dump_to_pp (pretty_printer *pp, bool simple) const
{
  if (simple)
    {
      pp_character (pp, '(');
      m_arg0->dump_to_pp (pp, simple);
      pp_string (pp, op_symbol_code (m_op));
      m_arg1->dump_to_pp (pp, simple);
      pp_character (pp, ')');
    }
  else
    {
      pp_string (pp, "binop_svalue (");
      pp_string (pp, get_tree_code_name (m_op));
      pp_string (pp, ", ");
      m_arg0->dump_to_pp (pp, simple);
      pp_string (pp, ", ");
      m_arg1->dump_to_pp (pp, simple);
      pp_character (pp, ')');
    }
}

/* Implementation of svalue::accept vfunc for binop_svalue.  */

void
binop_svalue::accept (visitor *v) const
{
  v->visit_binop_svalue (this);
  m_arg0->accept (v);
  m_arg1->accept (v);
}

/* Implementation of svalue::implicitly_live_p vfunc for binop_svalue.  */

bool
binop_svalue::implicitly_live_p (const svalue_set &live_svalues,
				 const region_model *model) const
{
  return (get_arg0 ()->live_p (live_svalues, model)
	  && get_arg1 ()->live_p (live_svalues, model));
}

/* class sub_svalue : public svalue.  */

/* sub_svalue'c ctor.  */

sub_svalue::sub_svalue (tree type, const svalue *parent_svalue,
			const region *subregion)
: svalue (complexity::from_pair (parent_svalue->get_complexity (),
				 subregion->get_complexity ()),
	  type),
  m_parent_svalue (parent_svalue), m_subregion (subregion)
{
}

/* Implementation of svalue::dump_to_pp vfunc for sub_svalue.  */

void
sub_svalue::dump_to_pp (pretty_printer *pp, bool simple) const
{
  if (simple)
    {
      pp_string (pp, "SUB(");
      m_parent_svalue->dump_to_pp (pp, simple);
      pp_string (pp, ", ");
      m_subregion->dump_to_pp (pp, simple);
      pp_character (pp, ')');
    }
  else
    {
      pp_string (pp, "sub_svalue (");
      pp_string (pp, ", ");
      m_parent_svalue->dump_to_pp (pp, simple);
      pp_string (pp, ", ");
      m_subregion->dump_to_pp (pp, simple);
      pp_character (pp, ')');
    }
}

/* Implementation of svalue::accept vfunc for sub_svalue.  */

void
sub_svalue::accept (visitor *v) const
{
  v->visit_sub_svalue (this);
  m_parent_svalue->accept (v);
  m_subregion->accept (v);
}

/* Implementation of svalue::implicitly_live_p vfunc for sub_svalue.  */

bool
sub_svalue::implicitly_live_p (const svalue_set &live_svalues,
			       const region_model *model) const
{
  return get_parent ()->live_p (live_svalues, model);
}

/* class widening_svalue : public svalue.  */

/* Implementation of svalue::dump_to_pp vfunc for widening_svalue.  */

void
widening_svalue::dump_to_pp (pretty_printer *pp, bool simple) const
{
  if (simple)
    {
      pp_string (pp, "WIDENING(");
      pp_character (pp, '{');
      m_point.print (pp, format (false));
      pp_string (pp, "}, ");
      m_base_sval->dump_to_pp (pp, simple);
      pp_string (pp, ", ");
      m_iter_sval->dump_to_pp (pp, simple);
      pp_character (pp, ')');
    }
  else
    {
      pp_string (pp, "widening_svalue (");
      pp_string (pp, ", ");
      pp_character (pp, '{');
      m_point.print (pp, format (false));
      pp_string (pp, "}, ");
      m_base_sval->dump_to_pp (pp, simple);
      pp_string (pp, ", ");
      m_iter_sval->dump_to_pp (pp, simple);
      pp_character (pp, ')');
    }
}

/* Implementation of svalue::accept vfunc for widening_svalue.  */

void
widening_svalue::accept (visitor *v) const
{
  v->visit_widening_svalue (this);
  m_base_sval->accept (v);
  m_iter_sval->accept (v);
}

/* Attempt to determine in which direction this value is changing
   w.r.t. the initial value.  */

enum widening_svalue::direction_t
widening_svalue::get_direction () const
{
  tree base_cst = m_base_sval->maybe_get_constant ();
  if (base_cst == NULL_TREE)
    return DIR_UNKNOWN;
  tree iter_cst = m_iter_sval->maybe_get_constant ();
  if (iter_cst == NULL_TREE)
    return DIR_UNKNOWN;

  tree iter_gt_base = fold_binary (GT_EXPR, boolean_type_node,
				   iter_cst, base_cst);
  if (iter_gt_base == boolean_true_node)
    return DIR_ASCENDING;

  tree iter_lt_base = fold_binary (LT_EXPR, boolean_type_node,
				   iter_cst, base_cst);
  if (iter_lt_base == boolean_true_node)
    return DIR_DESCENDING;

  return DIR_UNKNOWN;
}

/* Compare this value against constant RHS_CST.  */

tristate
widening_svalue::eval_condition_without_cm (enum tree_code op,
					    tree rhs_cst) const
{
  tree base_cst = m_base_sval->maybe_get_constant ();
  if (base_cst == NULL_TREE)
    return tristate::TS_UNKNOWN;
  tree iter_cst = m_iter_sval->maybe_get_constant ();
  if (iter_cst == NULL_TREE)
    return tristate::TS_UNKNOWN;

  switch (get_direction ())
    {
    default:
      gcc_unreachable ();
    case DIR_ASCENDING:
      /* LHS is in [base_cst, +ve infinity), assuming no overflow.  */
      switch (op)
	{
	case LE_EXPR:
	case LT_EXPR:
	  {
	    /* [BASE, +INF) OP RHS:
	       This is either true or false at +ve ininity,
	       It can be true for points X where X OP RHS, so we have either
	       "false", or "unknown".  */
	    tree base_op_rhs = fold_binary (op, boolean_type_node,
					    base_cst, rhs_cst);
	    if (base_op_rhs == boolean_true_node)
	      return tristate::TS_UNKNOWN;
	    else
	      return tristate::TS_FALSE;
	  }

	case GE_EXPR:
	case GT_EXPR:
	  {
	    /* [BASE, +INF) OP RHS:
	       This is true at +ve infinity.  It will be true everywhere
	       in the range if BASE >= RHS.  */
	    tree base_op_rhs = fold_binary (op, boolean_type_node,
					    base_cst, rhs_cst);
	    if (base_op_rhs == boolean_true_node)
	      return tristate::TS_TRUE;
	    else
	      return tristate::TS_UNKNOWN;
	  }

	case EQ_EXPR:
	  {
	    /* [BASE, +INF) == RHS:
	       Could this be true at any point in the range?  If so we
	       have "unknown", otherwise we have "false".  */
	    tree base_le_rhs = fold_binary (LE_EXPR, boolean_type_node,
					    base_cst, rhs_cst);
	    if (base_le_rhs == boolean_true_node)
	      return tristate::TS_UNKNOWN;
	    else
	      return tristate::TS_FALSE;
	  }

	case NE_EXPR:
	  {
	    /* [BASE, +INF) != RHS:
	       Could we have equality at any point in the range?  If so we
	       have "unknown", otherwise we have "true".  */
	    tree base_le_rhs = fold_binary (LE_EXPR, boolean_type_node,
					    base_cst, rhs_cst);
	    if (base_le_rhs == boolean_true_node)
	      return tristate::TS_UNKNOWN;
	    else
	      return tristate::TS_TRUE;
	  }

	default:
	  return tristate::TS_UNKNOWN;
	}

    case DIR_DESCENDING:
      /* LHS is in (-ve infinity, base_cst], assuming no overflow.  */
      return tristate::TS_UNKNOWN;

    case DIR_UNKNOWN:
      return tristate::TS_UNKNOWN;
    }
}

/* class placeholder_svalue : public svalue.  */

/* Implementation of svalue::dump_to_pp vfunc for placeholder_svalue.  */

void
placeholder_svalue::dump_to_pp (pretty_printer *pp, bool simple) const
{
  if (simple)
    pp_printf (pp, "PLACEHOLDER(%qs)", m_name);
  else
    pp_printf (pp, "placeholder_svalue (%qs)", m_name);
}

/* Implementation of svalue::accept vfunc for placeholder_svalue.  */

void
placeholder_svalue::accept (visitor *v) const
{
  v->visit_placeholder_svalue (this);
}

/* class unmergeable_svalue : public svalue.  */

/* Implementation of svalue::dump_to_pp vfunc for unmergeable_svalue.  */

void
unmergeable_svalue::dump_to_pp (pretty_printer *pp, bool simple) const
{
  if (simple)
    {
      pp_string (pp, "UNMERGEABLE(");
      m_arg->dump_to_pp (pp, simple);
      pp_character (pp, ')');
    }
  else
    {
      pp_string (pp, "unmergeable_svalue (");
      m_arg->dump_to_pp (pp, simple);
      pp_character (pp, ')');
    }
}

/* Implementation of svalue::accept vfunc for unmergeable_svalue.  */

void
unmergeable_svalue::accept (visitor *v) const
{
  v->visit_unmergeable_svalue (this);
  m_arg->accept (v);
}

/* Implementation of svalue::implicitly_live_p vfunc for unmergeable_svalue.  */

bool
unmergeable_svalue::implicitly_live_p (const svalue_set &live_svalues,
				       const region_model *model) const
{
  return get_arg ()->live_p (live_svalues, model);
}

/* class compound_svalue : public svalue.  */

compound_svalue::compound_svalue (tree type, const binding_map &map)
: svalue (calc_complexity (map), type), m_map (map)
{
  /* All keys within the underlying binding_map are required to be concrete,
     not symbolic.  */
#if CHECKING_P
  for (iterator_t iter = begin (); iter != end (); ++iter)
    {
      const binding_key *key = (*iter).first;
      gcc_assert (key->concrete_p ());
    }
#endif
}

/* Implementation of svalue::dump_to_pp vfunc for compound_svalue.  */

void
compound_svalue::dump_to_pp (pretty_printer *pp, bool simple) const
{
  if (simple)
    {
      pp_string (pp, "COMPOUND(");
      m_map.dump_to_pp (pp, simple, false);
      pp_character (pp, ')');
    }
  else
    {
      pp_string (pp, "compound_svalue (");
      pp_string (pp, ", ");
      pp_character (pp, '{');
      m_map.dump_to_pp (pp, simple, false);
      pp_string (pp, "}, ");
      pp_character (pp, ')');
    }
}

/* Implementation of svalue::accept vfunc for compound_svalue.  */

void
compound_svalue::accept (visitor *v) const
{
  v->visit_compound_svalue (this);
  for (binding_map::iterator_t iter = m_map.begin ();
       iter != m_map.end (); ++iter)
    {
      //(*iter).first.accept (v);
      (*iter).second->accept (v);
    }
}

/* Calculate what the complexity of a compound_svalue instance for MAP
   will be, based on the svalues bound within MAP.  */

complexity
compound_svalue::calc_complexity (const binding_map &map)
{
  unsigned num_child_nodes = 0;
  unsigned max_child_depth = 0;
  for (binding_map::iterator_t iter = map.begin ();
       iter != map.end (); ++iter)
    {
      const complexity &sval_c = (*iter).second->get_complexity ();
      num_child_nodes += sval_c.m_num_nodes;
      max_child_depth = MAX (max_child_depth, sval_c.m_max_depth);
    }
  return complexity (num_child_nodes + 1, max_child_depth + 1);
}

/* class conjured_svalue : public svalue.  */

/* Implementation of svalue::dump_to_pp vfunc for conjured_svalue.  */

void
conjured_svalue::dump_to_pp (pretty_printer *pp, bool simple) const
{
  if (simple)
    {
      pp_string (pp, "CONJURED(");
      pp_gimple_stmt_1 (pp, m_stmt, 0, (dump_flags_t)0);
      pp_string (pp, ", ");
      m_id_reg->dump_to_pp (pp, simple);
      pp_character (pp, ')');
    }
  else
    {
      pp_string (pp, "conjured_svalue (");
      pp_string (pp, ", ");
      pp_gimple_stmt_1 (pp, m_stmt, 0, (dump_flags_t)0);
      pp_string (pp, ", ");
      m_id_reg->dump_to_pp (pp, simple);
      pp_character (pp, ')');
    }
}

/* Implementation of svalue::accept vfunc for conjured_svalue.  */

void
conjured_svalue::accept (visitor *v) const
{
  v->visit_conjured_svalue (this);
  m_id_reg->accept (v);
}

} // namespace ana

#endif /* #if ENABLE_ANALYZER */
