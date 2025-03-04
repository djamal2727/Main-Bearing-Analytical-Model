------------------------------------------------------------------------------
--                                                                          --
--                         GNAT COMPILER COMPONENTS                         --
--                                                                          --
--                            C O N T R A C T S                             --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--          Copyright (C) 2015-2020, Free Software Foundation, Inc.         --
--                                                                          --
-- GNAT is free software;  you can  redistribute it  and/or modify it under --
-- terms of the  GNU General Public License as published  by the Free Soft- --
-- ware  Foundation;  either version 3,  or (at your option) any later ver- --
-- sion.  GNAT is distributed in the hope that it will be useful, but WITH- --
-- OUT ANY WARRANTY;  without even the  implied warranty of MERCHANTABILITY --
-- or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License --
-- for  more details.  You should have  received  a copy of the GNU General --
-- Public License  distributed with GNAT; see file COPYING3.  If not, go to --
-- http://www.gnu.org/licenses for a complete copy of the license.          --
--                                                                          --
-- GNAT was originally developed  by the GNAT team at  New York University. --
-- Extensive contributions were provided by Ada Core Technologies Inc.      --
--                                                                          --
------------------------------------------------------------------------------

with Aspects;  use Aspects;
with Atree;    use Atree;
with Einfo;    use Einfo;
with Elists;   use Elists;
with Errout;   use Errout;
with Exp_Prag; use Exp_Prag;
with Exp_Tss;  use Exp_Tss;
with Exp_Util; use Exp_Util;
with Freeze;   use Freeze;
with Lib;      use Lib;
with Namet;    use Namet;
with Nlists;   use Nlists;
with Nmake;    use Nmake;
with Opt;      use Opt;
with Sem;      use Sem;
with Sem_Aux;  use Sem_Aux;
with Sem_Ch6;  use Sem_Ch6;
with Sem_Ch8;  use Sem_Ch8;
with Sem_Ch12; use Sem_Ch12;
with Sem_Ch13; use Sem_Ch13;
with Sem_Disp; use Sem_Disp;
with Sem_Prag; use Sem_Prag;
with Sem_Util; use Sem_Util;
with Sinfo;    use Sinfo;
with Snames;   use Snames;
with Stand;    use Stand;
with Stringt;  use Stringt;
with Tbuild;   use Tbuild;

package body Contracts is

   procedure Analyze_Package_Instantiation_Contract (Inst_Id : Entity_Id);
   --  Analyze all delayed pragmas chained on the contract of package
   --  instantiation Inst_Id as if they appear at the end of a declarative
   --  region. The pragmas in question are:
   --
   --    Part_Of

   procedure Check_Type_Or_Object_External_Properties
     (Type_Or_Obj_Id : Entity_Id);
   --  Perform checking of external properties pragmas that is common to both
   --  type declarations and object declarations.

   procedure Expand_Subprogram_Contract (Body_Id : Entity_Id);
   --  Expand the contracts of a subprogram body and its correspoding spec (if
   --  any). This routine processes all [refined] pre- and postconditions as
   --  well as Contract_Cases, Subprogram_Variant, invariants and predicates.
   --  Body_Id denotes the entity of the subprogram body.

   -----------------------
   -- Add_Contract_Item --
   -----------------------

   procedure Add_Contract_Item (Prag : Node_Id; Id : Entity_Id) is
      Items : Node_Id := Contract (Id);

      procedure Add_Classification;
      --  Prepend Prag to the list of classifications

      procedure Add_Contract_Test_Case;
      --  Prepend Prag to the list of contract and test cases

      procedure Add_Pre_Post_Condition;
      --  Prepend Prag to the list of pre- and postconditions

      ------------------------
      -- Add_Classification --
      ------------------------

      procedure Add_Classification is
      begin
         Set_Next_Pragma (Prag, Classifications (Items));
         Set_Classifications (Items, Prag);
      end Add_Classification;

      ----------------------------
      -- Add_Contract_Test_Case --
      ----------------------------

      procedure Add_Contract_Test_Case is
      begin
         Set_Next_Pragma (Prag, Contract_Test_Cases (Items));
         Set_Contract_Test_Cases (Items, Prag);
      end Add_Contract_Test_Case;

      ----------------------------
      -- Add_Pre_Post_Condition --
      ----------------------------

      procedure Add_Pre_Post_Condition is
      begin
         Set_Next_Pragma (Prag, Pre_Post_Conditions (Items));
         Set_Pre_Post_Conditions (Items, Prag);
      end Add_Pre_Post_Condition;

      --  Local variables

      --  A contract must contain only pragmas

      pragma Assert (Nkind (Prag) = N_Pragma);
      Prag_Nam : constant Name_Id := Pragma_Name (Prag);

   --  Start of processing for Add_Contract_Item

   begin
      --  Create a new contract when adding the first item

      if No (Items) then
         Items := Make_Contract (Sloc (Id));
         Set_Contract (Id, Items);
      end if;

      --  Constants, the applicable pragmas are:
      --    Part_Of

      if Ekind (Id) = E_Constant then
         if Prag_Nam = Name_Part_Of then
            Add_Classification;

         --  The pragma is not a proper contract item

         else
            raise Program_Error;
         end if;

      --  Entry bodies, the applicable pragmas are:
      --    Refined_Depends
      --    Refined_Global
      --    Refined_Post

      elsif Is_Entry_Body (Id) then
         if Prag_Nam in Name_Refined_Depends | Name_Refined_Global then
            Add_Classification;

         elsif Prag_Nam = Name_Refined_Post then
            Add_Pre_Post_Condition;

         --  The pragma is not a proper contract item

         else
            raise Program_Error;
         end if;

      --  Entry or subprogram declarations, the applicable pragmas are:
      --    Attach_Handler
      --    Contract_Cases
      --    Depends
      --    Extensions_Visible
      --    Global
      --    Interrupt_Handler
      --    Postcondition
      --    Precondition
      --    Test_Case
      --    Volatile_Function

      elsif Is_Entry_Declaration (Id)
        or else Ekind (Id) in E_Function
                            | E_Generic_Function
                            | E_Generic_Procedure
                            | E_Procedure
      then
         if Prag_Nam in Name_Attach_Handler | Name_Interrupt_Handler
           and then Ekind (Id) in E_Generic_Procedure | E_Procedure
         then
            Add_Classification;

         elsif Prag_Nam in Name_Depends
                         | Name_Extensions_Visible
                         | Name_Global
         then
            Add_Classification;

         elsif Prag_Nam = Name_Volatile_Function
           and then Ekind (Id) in E_Function | E_Generic_Function
         then
            Add_Classification;

         elsif Prag_Nam in Name_Contract_Cases
                         | Name_Subprogram_Variant
                         | Name_Test_Case
         then
            Add_Contract_Test_Case;

         elsif Prag_Nam in Name_Postcondition | Name_Precondition then
            Add_Pre_Post_Condition;

         --  The pragma is not a proper contract item

         else
            raise Program_Error;
         end if;

      --  Packages or instantiations, the applicable pragmas are:
      --    Abstract_States
      --    Initial_Condition
      --    Initializes
      --    Part_Of (instantiation only)

      elsif Is_Package_Or_Generic_Package (Id) then
         if Prag_Nam in Name_Abstract_State
                      | Name_Initial_Condition
                      | Name_Initializes
         then
            Add_Classification;

         --  Indicator Part_Of must be associated with a package instantiation

         elsif Prag_Nam = Name_Part_Of and then Is_Generic_Instance (Id) then
            Add_Classification;

         --  The pragma is not a proper contract item

         else
            raise Program_Error;
         end if;

      --  Package bodies, the applicable pragmas are:
      --    Refined_States

      elsif Ekind (Id) = E_Package_Body then
         if Prag_Nam = Name_Refined_State then
            Add_Classification;

         --  The pragma is not a proper contract item

         else
            raise Program_Error;
         end if;

      --  The four volatility refinement pragmas are ok for all types.
      --  Part_Of is ok for task types and protected types.
      --  Depends and Global are ok for task types.

      elsif Is_Type (Id) then
         declare
            Is_OK : constant Boolean :=
              Prag_Nam in Name_Async_Readers
                        | Name_Async_Writers
                        | Name_Effective_Reads
                        | Name_Effective_Writes
              or else (Ekind (Id) = E_Task_Type
                         and Prag_Nam in Name_Part_Of
                                       | Name_Depends
                                       | Name_Global)
              or else (Ekind (Id) = E_Protected_Type
                         and Prag_Nam = Name_Part_Of);
         begin
            if Is_OK then
               Add_Classification;
            else

               --  The pragma is not a proper contract item

               raise Program_Error;
            end if;
         end;

      --  Subprogram bodies, the applicable pragmas are:
      --    Postcondition
      --    Precondition
      --    Refined_Depends
      --    Refined_Global
      --    Refined_Post

      elsif Ekind (Id) = E_Subprogram_Body then
         if Prag_Nam in Name_Refined_Depends | Name_Refined_Global then
            Add_Classification;

         elsif Prag_Nam in Name_Postcondition
                         | Name_Precondition
                         | Name_Refined_Post
         then
            Add_Pre_Post_Condition;

         --  The pragma is not a proper contract item

         else
            raise Program_Error;
         end if;

      --  Task bodies, the applicable pragmas are:
      --    Refined_Depends
      --    Refined_Global

      elsif Ekind (Id) = E_Task_Body then
         if Prag_Nam in Name_Refined_Depends | Name_Refined_Global then
            Add_Classification;

         --  The pragma is not a proper contract item

         else
            raise Program_Error;
         end if;

      --  Task units, the applicable pragmas are:
      --    Depends
      --    Global
      --    Part_Of

      --  Variables, the applicable pragmas are:
      --    Async_Readers
      --    Async_Writers
      --    Constant_After_Elaboration
      --    Depends
      --    Effective_Reads
      --    Effective_Writes
      --    Global
      --    No_Caching
      --    Part_Of

      elsif Ekind (Id) = E_Variable then
         if Prag_Nam in Name_Async_Readers
                      | Name_Async_Writers
                      | Name_Constant_After_Elaboration
                      | Name_Depends
                      | Name_Effective_Reads
                      | Name_Effective_Writes
                      | Name_Global
                      | Name_No_Caching
                      | Name_Part_Of
         then
            Add_Classification;

         --  The pragma is not a proper contract item

         else
            raise Program_Error;
         end if;

      else
         raise Program_Error;
      end if;
   end Add_Contract_Item;

   -----------------------
   -- Analyze_Contracts --
   -----------------------

   procedure Analyze_Contracts (L : List_Id) is
      Decl : Node_Id;

   begin
      Decl := First (L);
      while Present (Decl) loop

         --  Entry or subprogram declarations

         if Nkind (Decl) in N_Abstract_Subprogram_Declaration
                          | N_Entry_Declaration
                          | N_Generic_Subprogram_Declaration
                          | N_Subprogram_Declaration
         then
            declare
               Subp_Id : constant Entity_Id := Defining_Entity (Decl);

            begin
               Analyze_Entry_Or_Subprogram_Contract (Subp_Id);

               --  If analysis of a class-wide pre/postcondition indicates
               --  that a class-wide clone is needed, analyze its declaration
               --  now. Its body is created when the body of the original
               --  operation is analyzed (and rewritten).

               if Is_Subprogram (Subp_Id)
                 and then Present (Class_Wide_Clone (Subp_Id))
               then
                  Analyze (Unit_Declaration_Node (Class_Wide_Clone (Subp_Id)));
               end if;
            end;

         --  Entry or subprogram bodies

         elsif Nkind (Decl) in N_Entry_Body | N_Subprogram_Body then
            Analyze_Entry_Or_Subprogram_Body_Contract (Defining_Entity (Decl));

         --  Objects

         elsif Nkind (Decl) = N_Object_Declaration then
            Analyze_Object_Contract (Defining_Entity (Decl));

         --  Package instantiation

         elsif Nkind (Decl) = N_Package_Instantiation then
            Analyze_Package_Instantiation_Contract (Defining_Entity (Decl));

         --  Protected units

         elsif Nkind (Decl) in N_Protected_Type_Declaration
                             | N_Single_Protected_Declaration
         then
            Analyze_Protected_Contract (Defining_Entity (Decl));

         --  Subprogram body stubs

         elsif Nkind (Decl) = N_Subprogram_Body_Stub then
            Analyze_Subprogram_Body_Stub_Contract (Defining_Entity (Decl));

         --  Task units

         elsif Nkind (Decl) in N_Single_Task_Declaration
                             | N_Task_Type_Declaration
         then
            Analyze_Task_Contract (Defining_Entity (Decl));

         --  For type declarations, we need to do the preanalysis of Iterable
         --  and the 3 Xxx_Literal aspect specifications.

         --  Other type aspects need to be resolved here???

         elsif Nkind (Decl) = N_Private_Type_Declaration
           and then Present (Aspect_Specifications (Decl))
         then
            declare
               E  : constant Entity_Id  := Defining_Identifier (Decl);
               It : constant Node_Id    := Find_Aspect (E, Aspect_Iterable);
               I_Lit : constant Node_Id :=
                 Find_Aspect (E, Aspect_Integer_Literal);
               R_Lit : constant Node_Id :=
                 Find_Aspect (E, Aspect_Real_Literal);
               S_Lit : constant Node_Id :=
                 Find_Aspect (E, Aspect_String_Literal);

            begin
               if Present (It) then
                  Validate_Iterable_Aspect (E, It);
               end if;

               if Present (I_Lit) then
                  Validate_Literal_Aspect (E, I_Lit);
               end if;
               if Present (R_Lit) then
                  Validate_Literal_Aspect (E, R_Lit);
               end if;
               if Present (S_Lit) then
                  Validate_Literal_Aspect (E, S_Lit);
               end if;
            end;
         end if;

         if Nkind (Decl) in N_Full_Type_Declaration
                          | N_Private_Type_Declaration
                          | N_Task_Type_Declaration
                          | N_Protected_Type_Declaration
                          | N_Formal_Type_Declaration
         then
            Analyze_Type_Contract (Defining_Identifier (Decl));
         end if;

         Next (Decl);
      end loop;
   end Analyze_Contracts;

   -----------------------------------------------
   -- Analyze_Entry_Or_Subprogram_Body_Contract --
   -----------------------------------------------

   --  WARNING: This routine manages SPARK regions. Return statements must be
   --  replaced by gotos which jump to the end of the routine and restore the
   --  SPARK mode.

   procedure Analyze_Entry_Or_Subprogram_Body_Contract (Body_Id : Entity_Id) is
      Body_Decl : constant Node_Id   := Unit_Declaration_Node (Body_Id);
      Items     : constant Node_Id   := Contract (Body_Id);
      Spec_Id   : constant Entity_Id := Unique_Defining_Entity (Body_Decl);

      Saved_SM  : constant SPARK_Mode_Type := SPARK_Mode;
      Saved_SMP : constant Node_Id         := SPARK_Mode_Pragma;
      --  Save the SPARK_Mode-related data to restore on exit

   begin
      --  When a subprogram body declaration is illegal, its defining entity is
      --  left unanalyzed. There is nothing left to do in this case because the
      --  body lacks a contract, or even a proper Ekind.

      if Ekind (Body_Id) = E_Void then
         return;

      --  Do not analyze a contract multiple times

      elsif Present (Items) then
         if Analyzed (Items) then
            return;
         else
            Set_Analyzed (Items);
         end if;
      end if;

      --  Due to the timing of contract analysis, delayed pragmas may be
      --  subject to the wrong SPARK_Mode, usually that of the enclosing
      --  context. To remedy this, restore the original SPARK_Mode of the
      --  related subprogram body.

      Set_SPARK_Mode (Body_Id);

      --  Ensure that the contract cases or postconditions mention 'Result or
      --  define a post-state.

      Check_Result_And_Post_State (Body_Id);

      --  A stand-alone nonvolatile function body cannot have an effectively
      --  volatile formal parameter or return type (SPARK RM 7.1.3(9)). This
      --  check is relevant only when SPARK_Mode is on, as it is not a standard
      --  legality rule. The check is performed here because Volatile_Function
      --  is processed after the analysis of the related subprogram body. The
      --  check only applies to source subprograms and not to generated TSS
      --  subprograms.

      if SPARK_Mode = On
        and then Ekind (Body_Id) in E_Function | E_Generic_Function
        and then Comes_From_Source (Spec_Id)
        and then not Is_Volatile_Function (Body_Id)
      then
         Check_Nonvolatile_Function_Profile (Body_Id);
      end if;

      --  Restore the SPARK_Mode of the enclosing context after all delayed
      --  pragmas have been analyzed.

      Restore_SPARK_Mode (Saved_SM, Saved_SMP);

      --  Capture all global references in a generic subprogram body now that
      --  the contract has been analyzed.

      if Is_Generic_Declaration_Or_Body (Body_Decl) then
         Save_Global_References_In_Contract
           (Templ  => Original_Node (Body_Decl),
            Gen_Id => Spec_Id);
      end if;

      --  Deal with preconditions, [refined] postconditions, Contract_Cases,
      --  Subprogram_Variant, invariants and predicates associated with body
      --  and its spec. Do not expand the contract of subprogram body stubs.

      if Nkind (Body_Decl) = N_Subprogram_Body then
         Expand_Subprogram_Contract (Body_Id);
      end if;
   end Analyze_Entry_Or_Subprogram_Body_Contract;

   ------------------------------------------
   -- Analyze_Entry_Or_Subprogram_Contract --
   ------------------------------------------

   --  WARNING: This routine manages SPARK regions. Return statements must be
   --  replaced by gotos which jump to the end of the routine and restore the
   --  SPARK mode.

   procedure Analyze_Entry_Or_Subprogram_Contract
     (Subp_Id   : Entity_Id;
      Freeze_Id : Entity_Id := Empty)
   is
      Items     : constant Node_Id := Contract (Subp_Id);
      Subp_Decl : constant Node_Id := Unit_Declaration_Node (Subp_Id);

      Saved_SM  : constant SPARK_Mode_Type := SPARK_Mode;
      Saved_SMP : constant Node_Id         := SPARK_Mode_Pragma;
      --  Save the SPARK_Mode-related data to restore on exit

      Skip_Assert_Exprs : constant Boolean :=
                            Is_Entry (Subp_Id) and then not GNATprove_Mode;

      Depends  : Node_Id := Empty;
      Global   : Node_Id := Empty;
      Prag     : Node_Id;
      Prag_Nam : Name_Id;

   begin
      --  Do not analyze a contract multiple times

      if Present (Items) then
         if Analyzed (Items) then
            return;
         else
            Set_Analyzed (Items);
         end if;
      end if;

      --  Due to the timing of contract analysis, delayed pragmas may be
      --  subject to the wrong SPARK_Mode, usually that of the enclosing
      --  context. To remedy this, restore the original SPARK_Mode of the
      --  related subprogram body.

      Set_SPARK_Mode (Subp_Id);

      --  All subprograms carry a contract, but for some it is not significant
      --  and should not be processed.

      if not Has_Significant_Contract (Subp_Id) then
         null;

      elsif Present (Items) then

         --  Do not analyze the pre/postconditions of an entry declaration
         --  unless annotating the original tree for GNATprove. The
         --  real analysis occurs when the pre/postconditons are relocated to
         --  the contract wrapper procedure (see Build_Contract_Wrapper).

         if Skip_Assert_Exprs then
            null;

         --  Otherwise analyze the pre/postconditions.
         --  If these come from an aspect specification, their expressions
         --  might include references to types that are not frozen yet, in the
         --  case where the body is a rewritten expression function that is a
         --  completion, so freeze all types within before constructing the
         --  contract code.

         else
            declare
               Bod          : Node_Id;
               Freeze_Types : Boolean := False;

            begin
               if Present (Freeze_Id) then
                  Bod := Unit_Declaration_Node (Freeze_Id);

                  if Nkind (Bod) = N_Subprogram_Body
                    and then Was_Expression_Function (Bod)
                    and then Ekind (Subp_Id) = E_Function
                    and then Chars (Subp_Id) = Chars (Freeze_Id)
                    and then Subp_Id /= Freeze_Id
                  then
                     Freeze_Types := True;
                  end if;
               end if;

               Prag := Pre_Post_Conditions (Items);
               while Present (Prag) loop
                  if Freeze_Types
                    and then Present (Corresponding_Aspect (Prag))
                  then
                     Freeze_Expr_Types
                       (Def_Id => Subp_Id,
                        Typ    => Standard_Boolean,
                        Expr   =>
                          Expression
                            (First (Pragma_Argument_Associations (Prag))),
                        N      => Bod);
                  end if;

                  Analyze_Pre_Post_Condition_In_Decl_Part (Prag, Freeze_Id);
                  Prag := Next_Pragma (Prag);
               end loop;
            end;
         end if;

         --  Analyze contract-cases and test-cases

         Prag := Contract_Test_Cases (Items);
         while Present (Prag) loop
            Prag_Nam := Pragma_Name (Prag);

            if Prag_Nam = Name_Contract_Cases then

               --  Do not analyze the contract cases of an entry declaration
               --  unless annotating the original tree for GNATprove.
               --  The real analysis occurs when the contract cases are moved
               --  to the contract wrapper procedure (Build_Contract_Wrapper).

               if Skip_Assert_Exprs then
                  null;

               --  Otherwise analyze the contract cases

               else
                  Analyze_Contract_Cases_In_Decl_Part (Prag, Freeze_Id);
               end if;

            elsif Prag_Nam = Name_Subprogram_Variant then
               Analyze_Subprogram_Variant_In_Decl_Part (Prag);

            else
               pragma Assert (Prag_Nam = Name_Test_Case);
               Analyze_Test_Case_In_Decl_Part (Prag);
            end if;

            Prag := Next_Pragma (Prag);
         end loop;

         --  Analyze classification pragmas

         Prag := Classifications (Items);
         while Present (Prag) loop
            Prag_Nam := Pragma_Name (Prag);

            if Prag_Nam = Name_Depends then
               Depends := Prag;

            elsif Prag_Nam = Name_Global then
               Global := Prag;
            end if;

            Prag := Next_Pragma (Prag);
         end loop;

         --  Analyze Global first, as Depends may mention items classified in
         --  the global categorization.

         if Present (Global) then
            Analyze_Global_In_Decl_Part (Global);
         end if;

         --  Depends must be analyzed after Global in order to see the modes of
         --  all global items.

         if Present (Depends) then
            Analyze_Depends_In_Decl_Part (Depends);
         end if;

         --  Ensure that the contract cases or postconditions mention 'Result
         --  or define a post-state.

         Check_Result_And_Post_State (Subp_Id);
      end if;

      --  A nonvolatile function cannot have an effectively volatile formal
      --  parameter or return type (SPARK RM 7.1.3(9)). This check is relevant
      --  only when SPARK_Mode is on, as it is not a standard legality rule.
      --  The check is performed here because pragma Volatile_Function is
      --  processed after the analysis of the related subprogram declaration.

      if SPARK_Mode = On
        and then Ekind (Subp_Id) in E_Function | E_Generic_Function
        and then Comes_From_Source (Subp_Id)
        and then not Is_Volatile_Function (Subp_Id)
      then
         Check_Nonvolatile_Function_Profile (Subp_Id);
      end if;

      --  Restore the SPARK_Mode of the enclosing context after all delayed
      --  pragmas have been analyzed.

      Restore_SPARK_Mode (Saved_SM, Saved_SMP);

      --  Capture all global references in a generic subprogram now that the
      --  contract has been analyzed.

      if Is_Generic_Declaration_Or_Body (Subp_Decl) then
         Save_Global_References_In_Contract
           (Templ  => Original_Node (Subp_Decl),
            Gen_Id => Subp_Id);
      end if;
   end Analyze_Entry_Or_Subprogram_Contract;

   ----------------------------------------------
   -- Check_Type_Or_Object_External_Properties --
   ----------------------------------------------

   procedure Check_Type_Or_Object_External_Properties
     (Type_Or_Obj_Id : Entity_Id)
   is
      function Decl_Kind (Is_Type     : Boolean;
                          Object_Kind : String) return String;
      --  Returns "type" or Object_Kind, depending on Is_Type

      ---------------
      -- Decl_Kind --
      ---------------

      function Decl_Kind (Is_Type     : Boolean;
                          Object_Kind : String) return String is
      begin
         if Is_Type then
            return "type";
         else
            return Object_Kind;
         end if;
      end Decl_Kind;

      Is_Type_Id : constant Boolean := Is_Type (Type_Or_Obj_Id);

      --  Local variables

      AR_Val       : Boolean := False;
      AW_Val       : Boolean := False;
      ER_Val       : Boolean := False;
      EW_Val       : Boolean := False;
      Seen         : Boolean := False;
      Prag         : Node_Id;
      Obj_Typ      : Entity_Id;

   --  Start of processing for Check_Type_Or_Object_External_Properties

   begin
      --  Analyze all external properties

      if Is_Type_Id then
         Obj_Typ := Type_Or_Obj_Id;

         --  If the parent type of a derived type is volatile
         --  then the derived type inherits volatility-related flags.

         if Is_Derived_Type (Type_Or_Obj_Id) then
            declare
               Parent_Type : constant Entity_Id :=
                 Etype (Base_Type (Type_Or_Obj_Id));
            begin
               if Is_Effectively_Volatile (Parent_Type) then
                  AR_Val := Async_Readers_Enabled (Parent_Type);
                  AW_Val := Async_Writers_Enabled (Parent_Type);
                  ER_Val := Effective_Reads_Enabled (Parent_Type);
                  EW_Val := Effective_Writes_Enabled (Parent_Type);
               end if;
            end;
         end if;
      else
         Obj_Typ := Etype (Type_Or_Obj_Id);
      end if;

      Prag := Get_Pragma (Type_Or_Obj_Id, Pragma_Async_Readers);

      if Present (Prag) then
         declare
            Saved_AR_Val : constant Boolean := AR_Val;
         begin
            Analyze_External_Property_In_Decl_Part (Prag, AR_Val);
            Seen := True;
            if Saved_AR_Val and not AR_Val then
               Error_Msg_N
                 ("illegal non-confirming Async_Readers specification",
                  Prag);
            end if;
         end;
      end if;

      Prag := Get_Pragma (Type_Or_Obj_Id, Pragma_Async_Writers);

      if Present (Prag) then
         declare
            Saved_AW_Val : constant Boolean := AW_Val;
         begin
            Analyze_External_Property_In_Decl_Part (Prag, AW_Val);
            Seen := True;
            if Saved_AW_Val and not AW_Val then
               Error_Msg_N
                 ("illegal non-confirming Async_Writers specification",
                  Prag);
            end if;
         end;
      end if;

      Prag := Get_Pragma (Type_Or_Obj_Id, Pragma_Effective_Reads);

      if Present (Prag) then
         declare
            Saved_ER_Val : constant Boolean := ER_Val;
         begin
            Analyze_External_Property_In_Decl_Part (Prag, ER_Val);
            Seen := True;
            if Saved_ER_Val and not ER_Val then
               Error_Msg_N
                 ("illegal non-confirming Effective_Reads specification",
                  Prag);
            end if;
         end;
      end if;

      Prag := Get_Pragma (Type_Or_Obj_Id, Pragma_Effective_Writes);

      if Present (Prag) then
         declare
            Saved_EW_Val : constant Boolean := EW_Val;
         begin
            Analyze_External_Property_In_Decl_Part (Prag, EW_Val);
            Seen := True;
            if Saved_EW_Val and not EW_Val then
               Error_Msg_N
                 ("illegal non-confirming Effective_Writes specification",
                  Prag);
            end if;
         end;
      end if;

      --  Verify the mutual interaction of the various external properties

      if Seen then
         Check_External_Properties
           (Type_Or_Obj_Id, AR_Val, AW_Val, ER_Val, EW_Val);
      end if;

      --  The following checks are relevant only when SPARK_Mode is on, as
      --  they are not standard Ada legality rules. Internally generated
      --  temporaries are ignored.

      if SPARK_Mode = On and then Comes_From_Source (Type_Or_Obj_Id) then
         if Is_Effectively_Volatile (Type_Or_Obj_Id) then

            --  The declaration of an effectively volatile object or type must
            --  appear at the library level (SPARK RM 7.1.3(3), C.6(6)).

            if not Is_Library_Level_Entity (Type_Or_Obj_Id) then
               Error_Msg_N
                 ("effectively volatile "
                    & Decl_Kind (Is_Type     => Is_Type_Id,
                                 Object_Kind => "variable")
                    & " & must be declared at library level "
                    & "(SPARK RM 7.1.3(3))", Type_Or_Obj_Id);

            --  An object of a discriminated type cannot be effectively
            --  volatile except for protected objects (SPARK RM 7.1.3(5)).

            elsif Has_Discriminants (Obj_Typ)
              and then not Is_Protected_Type (Obj_Typ)
            then
               Error_Msg_N
                ("discriminated "
                   & Decl_Kind (Is_Type     => Is_Type_Id,
                                Object_Kind => "object")
                   & " & cannot be volatile",
                 Type_Or_Obj_Id);
            end if;

            --  An object decl shall be compatible with respect to volatility
            --  with its type (SPARK RM 7.1.3(2)).

            if not Is_Type_Id then
               if Is_Effectively_Volatile  (Obj_Typ) then
                  Check_Volatility_Compatibility
                    (Type_Or_Obj_Id, Obj_Typ,
                     "volatile object", "its type",
                     Srcpos_Bearer => Type_Or_Obj_Id);
               end if;

            --  A component of a composite type (in this case, the composite
            --  type is an array type) shall be compatible with respect to
            --  volatility with the composite type (SPARK RM 7.1.3(6)).

            elsif Is_Array_Type (Obj_Typ) then
               Check_Volatility_Compatibility
                 (Component_Type (Obj_Typ), Obj_Typ,
                  "component type", "its enclosing array type",
                  Srcpos_Bearer => Obj_Typ);

            --  A component of a composite type (in this case, the composite
            --  type is a record type) shall be compatible with respect to
            --  volatility with the composite type (SPARK RM 7.1.3(6)).

            elsif Is_Record_Type (Obj_Typ) then
               declare
                  Comp : Entity_Id := First_Component (Obj_Typ);
               begin
                  while Present (Comp) loop
                     Check_Volatility_Compatibility
                       (Etype (Comp), Obj_Typ,
                        "record component " & Get_Name_String (Chars (Comp)),
                        "its enclosing record type",
                        Srcpos_Bearer => Comp);
                     Next_Component (Comp);
                  end loop;
               end;
            end if;

         --  The type or object is not effectively volatile

         else
            --  A non-effectively volatile type cannot have effectively
            --  volatile components (SPARK RM 7.1.3(6)).

            if Is_Type_Id
              and then not Is_Effectively_Volatile (Type_Or_Obj_Id)
              and then Has_Volatile_Component (Type_Or_Obj_Id)
            then
               Error_Msg_N
                 ("non-volatile type & cannot have volatile"
                    & " components",
                  Type_Or_Obj_Id);
            end if;
         end if;
      end if;
   end Check_Type_Or_Object_External_Properties;

   -----------------------------
   -- Analyze_Object_Contract --
   -----------------------------

   --  WARNING: This routine manages SPARK regions. Return statements must be
   --  replaced by gotos which jump to the end of the routine and restore the
   --  SPARK mode.

   procedure Analyze_Object_Contract
     (Obj_Id    : Entity_Id;
      Freeze_Id : Entity_Id := Empty)
   is
      Obj_Typ : constant Entity_Id := Etype (Obj_Id);

      Saved_SM  : constant SPARK_Mode_Type := SPARK_Mode;
      Saved_SMP : constant Node_Id         := SPARK_Mode_Pragma;
      --  Save the SPARK_Mode-related data to restore on exit

      NC_Val   : Boolean := False;
      Items    : Node_Id;
      Prag     : Node_Id;
      Ref_Elmt : Elmt_Id;

   begin
      --  The loop parameter in an element iterator over a formal container
      --  is declared with an object declaration, but no contracts apply.

      if Ekind (Obj_Id) = E_Loop_Parameter then
         return;
      end if;

      --  Do not analyze a contract multiple times

      Items := Contract (Obj_Id);

      if Present (Items) then
         if Analyzed (Items) then
            return;
         else
            Set_Analyzed (Items);
         end if;
      end if;

      --  The anonymous object created for a single concurrent type inherits
      --  the SPARK_Mode from the type. Due to the timing of contract analysis,
      --  delayed pragmas may be subject to the wrong SPARK_Mode, usually that
      --  of the enclosing context. To remedy this, restore the original mode
      --  of the related anonymous object.

      if Is_Single_Concurrent_Object (Obj_Id)
        and then Present (SPARK_Pragma (Obj_Id))
      then
         Set_SPARK_Mode (Obj_Id);
      end if;

      --  Constant-related checks

      if Ekind (Obj_Id) = E_Constant then

         --  Analyze indicator Part_Of

         Prag := Get_Pragma (Obj_Id, Pragma_Part_Of);

         --  Check whether the lack of indicator Part_Of agrees with the
         --  placement of the constant with respect to the state space.

         if No (Prag) then
            Check_Missing_Part_Of (Obj_Id);
         end if;

         --  A constant cannot be effectively volatile (SPARK RM 7.1.3(4)).
         --  This check is relevant only when SPARK_Mode is on, as it is not
         --  a standard Ada legality rule. Internally-generated constants that
         --  map generic formals to actuals in instantiations are allowed to
         --  be volatile.

         if SPARK_Mode = On
           and then Comes_From_Source (Obj_Id)
           and then Is_Effectively_Volatile (Obj_Id)
           and then No (Corresponding_Generic_Association (Parent (Obj_Id)))
         then
            Error_Msg_N ("constant cannot be volatile", Obj_Id);
         end if;

      --  Variable-related checks

      else pragma Assert (Ekind (Obj_Id) = E_Variable);

         Check_Type_Or_Object_External_Properties
           (Type_Or_Obj_Id => Obj_Id);

         --  Analyze the non-external volatility property No_Caching

         Prag := Get_Pragma (Obj_Id, Pragma_No_Caching);

         if Present (Prag) then
            Analyze_External_Property_In_Decl_Part (Prag, NC_Val);
         end if;

         --  The anonymous object created for a single task type carries
         --  pragmas Depends and Global of the type.

         if Is_Single_Task_Object (Obj_Id) then

            --  Analyze Global first, as Depends may mention items classified
            --  in the global categorization.

            Prag := Get_Pragma (Obj_Id, Pragma_Global);

            if Present (Prag) then
               Analyze_Global_In_Decl_Part (Prag);
            end if;

            --  Depends must be analyzed after Global in order to see the modes
            --  of all global items.

            Prag := Get_Pragma (Obj_Id, Pragma_Depends);

            if Present (Prag) then
               Analyze_Depends_In_Decl_Part (Prag);
            end if;
         end if;

         Prag := Get_Pragma (Obj_Id, Pragma_Part_Of);

         --  Analyze indicator Part_Of

         if Present (Prag) then
            Analyze_Part_Of_In_Decl_Part (Prag, Freeze_Id);

            --  The variable is a constituent of a single protected/task type
            --  and behaves as a component of the type. Verify that references
            --  to the variable occur within the definition or body of the type
            --  (SPARK RM 9.3).

            if Present (Encapsulating_State (Obj_Id))
              and then Is_Single_Concurrent_Object
                         (Encapsulating_State (Obj_Id))
              and then Present (Part_Of_References (Obj_Id))
            then
               Ref_Elmt := First_Elmt (Part_Of_References (Obj_Id));
               while Present (Ref_Elmt) loop
                  Check_Part_Of_Reference (Obj_Id, Node (Ref_Elmt));
                  Next_Elmt (Ref_Elmt);
               end loop;
            end if;

         --  Otherwise check whether the lack of indicator Part_Of agrees with
         --  the placement of the variable with respect to the state space.

         else
            Check_Missing_Part_Of (Obj_Id);
         end if;
      end if;

      --  Common checks

      if Comes_From_Source (Obj_Id) and then Is_Ghost_Entity (Obj_Id) then

         --  A Ghost object cannot be of a type that yields a synchronized
         --  object (SPARK RM 6.9(19)).

         if Yields_Synchronized_Object (Obj_Typ) then
            Error_Msg_N ("ghost object & cannot be synchronized", Obj_Id);

         --  A Ghost object cannot be effectively volatile (SPARK RM 6.9(7) and
         --  SPARK RM 6.9(19)).

         elsif Is_Effectively_Volatile (Obj_Id) then
            Error_Msg_N ("ghost object & cannot be volatile", Obj_Id);

         --  A Ghost object cannot be imported or exported (SPARK RM 6.9(7)).
         --  One exception to this is the object that represents the dispatch
         --  table of a Ghost tagged type, as the symbol needs to be exported.

         elsif Is_Exported (Obj_Id) then
            Error_Msg_N ("ghost object & cannot be exported", Obj_Id);

         elsif Is_Imported (Obj_Id) then
            Error_Msg_N ("ghost object & cannot be imported", Obj_Id);
         end if;
      end if;

      --  Restore the SPARK_Mode of the enclosing context after all delayed
      --  pragmas have been analyzed.

      Restore_SPARK_Mode (Saved_SM, Saved_SMP);
   end Analyze_Object_Contract;

   -----------------------------------
   -- Analyze_Package_Body_Contract --
   -----------------------------------

   --  WARNING: This routine manages SPARK regions. Return statements must be
   --  replaced by gotos which jump to the end of the routine and restore the
   --  SPARK mode.

   procedure Analyze_Package_Body_Contract
     (Body_Id   : Entity_Id;
      Freeze_Id : Entity_Id := Empty)
   is
      Body_Decl : constant Node_Id   := Unit_Declaration_Node (Body_Id);
      Items     : constant Node_Id   := Contract (Body_Id);
      Spec_Id   : constant Entity_Id := Spec_Entity (Body_Id);

      Saved_SM  : constant SPARK_Mode_Type := SPARK_Mode;
      Saved_SMP : constant Node_Id         := SPARK_Mode_Pragma;
      --  Save the SPARK_Mode-related data to restore on exit

      Ref_State : Node_Id;

   begin
      --  Do not analyze a contract multiple times

      if Present (Items) then
         if Analyzed (Items) then
            return;
         else
            Set_Analyzed (Items);
         end if;
      end if;

      --  Due to the timing of contract analysis, delayed pragmas may be
      --  subject to the wrong SPARK_Mode, usually that of the enclosing
      --  context. To remedy this, restore the original SPARK_Mode of the
      --  related package body.

      Set_SPARK_Mode (Body_Id);

      Ref_State := Get_Pragma (Body_Id, Pragma_Refined_State);

      --  The analysis of pragma Refined_State detects whether the spec has
      --  abstract states available for refinement.

      if Present (Ref_State) then
         Analyze_Refined_State_In_Decl_Part (Ref_State, Freeze_Id);
      end if;

      --  Restore the SPARK_Mode of the enclosing context after all delayed
      --  pragmas have been analyzed.

      Restore_SPARK_Mode (Saved_SM, Saved_SMP);

      --  Capture all global references in a generic package body now that the
      --  contract has been analyzed.

      if Is_Generic_Declaration_Or_Body (Body_Decl) then
         Save_Global_References_In_Contract
           (Templ  => Original_Node (Body_Decl),
            Gen_Id => Spec_Id);
      end if;
   end Analyze_Package_Body_Contract;

   ------------------------------
   -- Analyze_Package_Contract --
   ------------------------------

   --  WARNING: This routine manages SPARK regions. Return statements must be
   --  replaced by gotos which jump to the end of the routine and restore the
   --  SPARK mode.

   procedure Analyze_Package_Contract (Pack_Id : Entity_Id) is
      Items     : constant Node_Id := Contract (Pack_Id);
      Pack_Decl : constant Node_Id := Unit_Declaration_Node (Pack_Id);

      Saved_SM  : constant SPARK_Mode_Type := SPARK_Mode;
      Saved_SMP : constant Node_Id         := SPARK_Mode_Pragma;
      --  Save the SPARK_Mode-related data to restore on exit

      Init      : Node_Id := Empty;
      Init_Cond : Node_Id := Empty;
      Prag      : Node_Id;
      Prag_Nam  : Name_Id;

   begin
      --  Do not analyze a contract multiple times

      if Present (Items) then
         if Analyzed (Items) then
            return;
         else
            Set_Analyzed (Items);
         end if;
      end if;

      --  Due to the timing of contract analysis, delayed pragmas may be
      --  subject to the wrong SPARK_Mode, usually that of the enclosing
      --  context. To remedy this, restore the original SPARK_Mode of the
      --  related package.

      Set_SPARK_Mode (Pack_Id);

      if Present (Items) then

         --  Locate and store pragmas Initial_Condition and Initializes, since
         --  their order of analysis matters.

         Prag := Classifications (Items);
         while Present (Prag) loop
            Prag_Nam := Pragma_Name (Prag);

            if Prag_Nam = Name_Initial_Condition then
               Init_Cond := Prag;

            elsif Prag_Nam = Name_Initializes then
               Init := Prag;
            end if;

            Prag := Next_Pragma (Prag);
         end loop;

         --  Analyze the initialization-related pragmas. Initializes must come
         --  before Initial_Condition due to item dependencies.

         if Present (Init) then
            Analyze_Initializes_In_Decl_Part (Init);
         end if;

         if Present (Init_Cond) then
            Analyze_Initial_Condition_In_Decl_Part (Init_Cond);
         end if;
      end if;

      --  Restore the SPARK_Mode of the enclosing context after all delayed
      --  pragmas have been analyzed.

      Restore_SPARK_Mode (Saved_SM, Saved_SMP);

      --  Capture all global references in a generic package now that the
      --  contract has been analyzed.

      if Is_Generic_Declaration_Or_Body (Pack_Decl) then
         Save_Global_References_In_Contract
           (Templ  => Original_Node (Pack_Decl),
            Gen_Id => Pack_Id);
      end if;
   end Analyze_Package_Contract;

   --------------------------------------------
   -- Analyze_Package_Instantiation_Contract --
   --------------------------------------------

   --  WARNING: This routine manages SPARK regions. Return statements must be
   --  replaced by gotos which jump to the end of the routine and restore the
   --  SPARK mode.

   procedure Analyze_Package_Instantiation_Contract (Inst_Id : Entity_Id) is
      Inst_Spec : constant Node_Id :=
                    Instance_Spec (Unit_Declaration_Node (Inst_Id));

      Saved_SM  : constant SPARK_Mode_Type := SPARK_Mode;
      Saved_SMP : constant Node_Id         := SPARK_Mode_Pragma;
      --  Save the SPARK_Mode-related data to restore on exit

      Pack_Id : Entity_Id;
      Prag    : Node_Id;

   begin
      --  Nothing to do when the package instantiation is erroneous or left
      --  partially decorated.

      if No (Inst_Spec) then
         return;
      end if;

      Pack_Id := Defining_Entity (Inst_Spec);
      Prag    := Get_Pragma (Pack_Id, Pragma_Part_Of);

      --  Due to the timing of contract analysis, delayed pragmas may be
      --  subject to the wrong SPARK_Mode, usually that of the enclosing
      --  context. To remedy this, restore the original SPARK_Mode of the
      --  related package.

      Set_SPARK_Mode (Pack_Id);

      --  Check whether the lack of indicator Part_Of agrees with the placement
      --  of the package instantiation with respect to the state space. Nested
      --  package instantiations do not need to be checked because they inherit
      --  Part_Of indicator of the outermost package instantiation (see routine
      --  Propagate_Part_Of in Sem_Prag).

      if In_Instance then
         null;

      elsif No (Prag) then
         Check_Missing_Part_Of (Pack_Id);
      end if;

      --  Restore the SPARK_Mode of the enclosing context after all delayed
      --  pragmas have been analyzed.

      Restore_SPARK_Mode (Saved_SM, Saved_SMP);
   end Analyze_Package_Instantiation_Contract;

   --------------------------------
   -- Analyze_Protected_Contract --
   --------------------------------

   procedure Analyze_Protected_Contract (Prot_Id : Entity_Id) is
      Items : constant Node_Id := Contract (Prot_Id);

   begin
      --  Do not analyze a contract multiple times

      if Present (Items) then
         if Analyzed (Items) then
            return;
         else
            Set_Analyzed (Items);
         end if;
      end if;
   end Analyze_Protected_Contract;

   -------------------------------------------
   -- Analyze_Subprogram_Body_Stub_Contract --
   -------------------------------------------

   procedure Analyze_Subprogram_Body_Stub_Contract (Stub_Id : Entity_Id) is
      Stub_Decl : constant Node_Id   := Parent (Parent (Stub_Id));
      Spec_Id   : constant Entity_Id := Corresponding_Spec_Of_Stub (Stub_Decl);

   begin
      --  A subprogram body stub may act as its own spec or as the completion
      --  of a previous declaration. Depending on the context, the contract of
      --  the stub may contain two sets of pragmas.

      --  The stub is a completion, the applicable pragmas are:
      --    Refined_Depends
      --    Refined_Global

      if Present (Spec_Id) then
         Analyze_Entry_Or_Subprogram_Body_Contract (Stub_Id);

      --  The stub acts as its own spec, the applicable pragmas are:
      --    Contract_Cases
      --    Depends
      --    Global
      --    Postcondition
      --    Precondition
      --    Test_Case

      else
         Analyze_Entry_Or_Subprogram_Contract (Stub_Id);
      end if;
   end Analyze_Subprogram_Body_Stub_Contract;

   ---------------------------
   -- Analyze_Task_Contract --
   ---------------------------

   --  WARNING: This routine manages SPARK regions. Return statements must be
   --  replaced by gotos which jump to the end of the routine and restore the
   --  SPARK mode.

   procedure Analyze_Task_Contract (Task_Id : Entity_Id) is
      Items : constant Node_Id := Contract (Task_Id);

      Saved_SM  : constant SPARK_Mode_Type := SPARK_Mode;
      Saved_SMP : constant Node_Id         := SPARK_Mode_Pragma;
      --  Save the SPARK_Mode-related data to restore on exit

      Prag : Node_Id;

   begin
      --  Do not analyze a contract multiple times

      if Present (Items) then
         if Analyzed (Items) then
            return;
         else
            Set_Analyzed (Items);
         end if;
      end if;

      --  Due to the timing of contract analysis, delayed pragmas may be
      --  subject to the wrong SPARK_Mode, usually that of the enclosing
      --  context. To remedy this, restore the original SPARK_Mode of the
      --  related task unit.

      Set_SPARK_Mode (Task_Id);

      --  Analyze Global first, as Depends may mention items classified in the
      --  global categorization.

      Prag := Get_Pragma (Task_Id, Pragma_Global);

      if Present (Prag) then
         Analyze_Global_In_Decl_Part (Prag);
      end if;

      --  Depends must be analyzed after Global in order to see the modes of
      --  all global items.

      Prag := Get_Pragma (Task_Id, Pragma_Depends);

      if Present (Prag) then
         Analyze_Depends_In_Decl_Part (Prag);
      end if;

      --  Restore the SPARK_Mode of the enclosing context after all delayed
      --  pragmas have been analyzed.

      Restore_SPARK_Mode (Saved_SM, Saved_SMP);
   end Analyze_Task_Contract;

   ---------------------------
   -- Analyze_Type_Contract --
   ---------------------------

   procedure Analyze_Type_Contract (Type_Id : Entity_Id) is
   begin
      Check_Type_Or_Object_External_Properties
        (Type_Or_Obj_Id => Type_Id);
   end Analyze_Type_Contract;

   -----------------------------
   -- Create_Generic_Contract --
   -----------------------------

   procedure Create_Generic_Contract (Unit : Node_Id) is
      Templ    : constant Node_Id   := Original_Node (Unit);
      Templ_Id : constant Entity_Id := Defining_Entity (Templ);

      procedure Add_Generic_Contract_Pragma (Prag : Node_Id);
      --  Add a single contract-related source pragma Prag to the contract of
      --  generic template Templ_Id.

      ---------------------------------
      -- Add_Generic_Contract_Pragma --
      ---------------------------------

      procedure Add_Generic_Contract_Pragma (Prag : Node_Id) is
         Prag_Templ : Node_Id;

      begin
         --  Mark the pragma to prevent the premature capture of global
         --  references when capturing global references of the context
         --  (see Save_References_In_Pragma).

         Set_Is_Generic_Contract_Pragma (Prag);

         --  Pragmas that apply to a generic subprogram declaration are not
         --  part of the semantic structure of the generic template:

         --    generic
         --    procedure Example (Formal : Integer);
         --    pragma Precondition (Formal > 0);

         --  Create a generic template for such pragmas and link the template
         --  of the pragma with the generic template.

         if Nkind (Templ) = N_Generic_Subprogram_Declaration then
            Rewrite
              (Prag, Copy_Generic_Node (Prag, Empty, Instantiating => False));
            Prag_Templ := Original_Node (Prag);

            Set_Is_Generic_Contract_Pragma (Prag_Templ);
            Add_Contract_Item (Prag_Templ, Templ_Id);

         --  Otherwise link the pragma with the generic template

         else
            Add_Contract_Item (Prag, Templ_Id);
         end if;
      end Add_Generic_Contract_Pragma;

      --  Local variables

      Context : constant Node_Id   := Parent (Unit);
      Decl    : Node_Id := Empty;

   --  Start of processing for Create_Generic_Contract

   begin
      --  A generic package declaration carries contract-related source pragmas
      --  in its visible declarations.

      if Nkind (Templ) = N_Generic_Package_Declaration then
         Set_Ekind (Templ_Id, E_Generic_Package);

         if Present (Visible_Declarations (Specification (Templ))) then
            Decl := First (Visible_Declarations (Specification (Templ)));
         end if;

      --  A generic package body carries contract-related source pragmas in its
      --  declarations.

      elsif Nkind (Templ) = N_Package_Body then
         Set_Ekind (Templ_Id, E_Package_Body);

         if Present (Declarations (Templ)) then
            Decl := First (Declarations (Templ));
         end if;

      --  Generic subprogram declaration

      elsif Nkind (Templ) = N_Generic_Subprogram_Declaration then
         if Nkind (Specification (Templ)) = N_Function_Specification then
            Set_Ekind (Templ_Id, E_Generic_Function);
         else
            Set_Ekind (Templ_Id, E_Generic_Procedure);
         end if;

         --  When the generic subprogram acts as a compilation unit, inspect
         --  the Pragmas_After list for contract-related source pragmas.

         if Nkind (Context) = N_Compilation_Unit then
            if Present (Aux_Decls_Node (Context))
              and then Present (Pragmas_After (Aux_Decls_Node (Context)))
            then
               Decl := First (Pragmas_After (Aux_Decls_Node (Context)));
            end if;

         --  Otherwise inspect the successive declarations for contract-related
         --  source pragmas.

         else
            Decl := Next (Unit);
         end if;

      --  A generic subprogram body carries contract-related source pragmas in
      --  its declarations.

      elsif Nkind (Templ) = N_Subprogram_Body then
         Set_Ekind (Templ_Id, E_Subprogram_Body);

         if Present (Declarations (Templ)) then
            Decl := First (Declarations (Templ));
         end if;
      end if;

      --  Inspect the relevant declarations looking for contract-related source
      --  pragmas and add them to the contract of the generic unit.

      while Present (Decl) loop
         if Comes_From_Source (Decl) then
            if Nkind (Decl) = N_Pragma then

               --  The source pragma is a contract annotation

               if Is_Contract_Annotation (Decl) then
                  Add_Generic_Contract_Pragma (Decl);
               end if;

            --  The region where a contract-related source pragma may appear
            --  ends with the first source non-pragma declaration or statement.

            else
               exit;
            end if;
         end if;

         Next (Decl);
      end loop;
   end Create_Generic_Contract;

   --------------------------------
   -- Expand_Subprogram_Contract --
   --------------------------------

   procedure Expand_Subprogram_Contract (Body_Id : Entity_Id) is
      Body_Decl : constant Node_Id   := Unit_Declaration_Node (Body_Id);
      Spec_Id   : constant Entity_Id := Corresponding_Spec (Body_Decl);

      procedure Add_Invariant_And_Predicate_Checks
        (Subp_Id : Entity_Id;
         Stmts   : in out List_Id;
         Result  : out Node_Id);
      --  Process the result of function Subp_Id (if applicable) and all its
      --  formals. Add invariant and predicate checks where applicable. The
      --  routine appends all the checks to list Stmts. If Subp_Id denotes a
      --  function, Result contains the entity of parameter _Result, to be
      --  used in the creation of procedure _Postconditions.

      procedure Append_Enabled_Item (Item : Node_Id; List : in out List_Id);
      --  Append a node to a list. If there is no list, create a new one. When
      --  the item denotes a pragma, it is added to the list only when it is
      --  enabled.

      procedure Build_Postconditions_Procedure
        (Subp_Id : Entity_Id;
         Stmts   : List_Id;
         Result  : Entity_Id);
      --  Create the body of procedure _Postconditions which handles various
      --  assertion actions on exit from subprogram Subp_Id. Stmts is the list
      --  of statements to be checked on exit. Parameter Result is the entity
      --  of parameter _Result when Subp_Id denotes a function.

      procedure Process_Contract_Cases (Stmts : in out List_Id);
      --  Process pragma Contract_Cases. This routine prepends items to the
      --  body declarations and appends items to list Stmts.

      procedure Process_Postconditions (Stmts : in out List_Id);
      --  Collect all [inherited] spec and body postconditions and accumulate
      --  their pragma Check equivalents in list Stmts.

      procedure Process_Preconditions;
      --  Collect all [inherited] spec and body preconditions and prepend their
      --  pragma Check equivalents to the declarations of the body.

      ----------------------------------------
      -- Add_Invariant_And_Predicate_Checks --
      ----------------------------------------

      procedure Add_Invariant_And_Predicate_Checks
        (Subp_Id : Entity_Id;
         Stmts   : in out List_Id;
         Result  : out Node_Id)
      is
         procedure Add_Invariant_Access_Checks (Id : Entity_Id);
         --  Id denotes the return value of a function or a formal parameter.
         --  Add an invariant check if the type of Id is access to a type with
         --  invariants. The routine appends the generated code to Stmts.

         function Invariant_Checks_OK (Typ : Entity_Id) return Boolean;
         --  Determine whether type Typ can benefit from invariant checks. To
         --  qualify, the type must have a non-null invariant procedure and
         --  subprogram Subp_Id must appear visible from the point of view of
         --  the type.

         ---------------------------------
         -- Add_Invariant_Access_Checks --
         ---------------------------------

         procedure Add_Invariant_Access_Checks (Id : Entity_Id) is
            Loc : constant Source_Ptr := Sloc (Body_Decl);
            Ref : Node_Id;
            Typ : Entity_Id;

         begin
            Typ := Etype (Id);

            if Is_Access_Type (Typ) and then not Is_Access_Constant (Typ) then
               Typ := Designated_Type (Typ);

               if Invariant_Checks_OK (Typ) then
                  Ref :=
                    Make_Explicit_Dereference (Loc,
                      Prefix => New_Occurrence_Of (Id, Loc));
                  Set_Etype (Ref, Typ);

                  --  Generate:
                  --    if <Id> /= null then
                  --       <invariant_call (<Ref>)>
                  --    end if;

                  Append_Enabled_Item
                    (Item =>
                       Make_If_Statement (Loc,
                         Condition =>
                           Make_Op_Ne (Loc,
                             Left_Opnd  => New_Occurrence_Of (Id, Loc),
                             Right_Opnd => Make_Null (Loc)),
                         Then_Statements => New_List (
                           Make_Invariant_Call (Ref))),
                     List => Stmts);
               end if;
            end if;
         end Add_Invariant_Access_Checks;

         -------------------------
         -- Invariant_Checks_OK --
         -------------------------

         function Invariant_Checks_OK (Typ : Entity_Id) return Boolean is
            function Has_Public_Visibility_Of_Subprogram return Boolean;
            --  Determine whether type Typ has public visibility of subprogram
            --  Subp_Id.

            -----------------------------------------
            -- Has_Public_Visibility_Of_Subprogram --
            -----------------------------------------

            function Has_Public_Visibility_Of_Subprogram return Boolean is
               Subp_Decl : constant Node_Id := Unit_Declaration_Node (Subp_Id);

            begin
               --  An Initialization procedure must be considered visible even
               --  though it is internally generated.

               if Is_Init_Proc (Defining_Entity (Subp_Decl)) then
                  return True;

               elsif Ekind (Scope (Typ)) /= E_Package then
                  return False;

               --  Internally generated code is never publicly visible except
               --  for a subprogram that is the implementation of an expression
               --  function. In that case the visibility is determined by the
               --  last check.

               elsif not Comes_From_Source (Subp_Decl)
                 and then
                   (Nkind (Original_Node (Subp_Decl)) /= N_Expression_Function
                      or else not
                        Comes_From_Source (Defining_Entity (Subp_Decl)))
               then
                  return False;

               --  Determine whether the subprogram is declared in the visible
               --  declarations of the package containing the type, or in the
               --  visible declaration of a child unit of that package.

               else
                  declare
                     Decls      : constant List_Id   :=
                                    List_Containing (Subp_Decl);
                     Subp_Scope : constant Entity_Id :=
                                    Scope (Defining_Entity (Subp_Decl));
                     Typ_Scope  : constant Entity_Id := Scope (Typ);

                  begin
                     return
                       Decls = Visible_Declarations
                           (Specification (Unit_Declaration_Node (Typ_Scope)))

                         or else
                           (Ekind (Subp_Scope) = E_Package
                             and then Typ_Scope /= Subp_Scope
                             and then Is_Child_Unit (Subp_Scope)
                             and then
                               Is_Ancestor_Package (Typ_Scope, Subp_Scope)
                             and then
                               Decls = Visible_Declarations
                                 (Specification
                                   (Unit_Declaration_Node (Subp_Scope))));
                  end;
               end if;
            end Has_Public_Visibility_Of_Subprogram;

         --  Start of processing for Invariant_Checks_OK

         begin
            return
              Has_Invariants (Typ)
                and then Present (Invariant_Procedure (Typ))
                and then not Has_Null_Body (Invariant_Procedure (Typ))
                and then Has_Public_Visibility_Of_Subprogram;
         end Invariant_Checks_OK;

         --  Local variables

         Loc : constant Source_Ptr := Sloc (Body_Decl);
         --  Source location of subprogram body contract

         Formal : Entity_Id;
         Typ    : Entity_Id;

      --  Start of processing for Add_Invariant_And_Predicate_Checks

      begin
         Result := Empty;

         --  Process the result of a function

         if Ekind (Subp_Id) = E_Function then
            Typ := Etype (Subp_Id);

            --  Generate _Result which is used in procedure _Postconditions to
            --  verify the return value.

            Result := Make_Defining_Identifier (Loc, Name_uResult);
            Set_Etype (Result, Typ);

            --  Add an invariant check when the return type has invariants and
            --  the related function is visible to the outside.

            if Invariant_Checks_OK (Typ) then
               Append_Enabled_Item
                 (Item =>
                    Make_Invariant_Call (New_Occurrence_Of (Result, Loc)),
                  List => Stmts);
            end if;

            --  Add an invariant check when the return type is an access to a
            --  type with invariants.

            Add_Invariant_Access_Checks (Result);
         end if;

         --  Add invariant checks for all formals that qualify (see AI05-0289
         --  and AI12-0044).

         Formal := First_Formal (Subp_Id);
         while Present (Formal) loop
            Typ := Etype (Formal);

            if Ekind (Formal) /= E_In_Parameter
              or else Ekind (Subp_Id) = E_Procedure
              or else Is_Access_Type (Typ)
            then
               if Invariant_Checks_OK (Typ) then
                  Append_Enabled_Item
                    (Item =>
                       Make_Invariant_Call (New_Occurrence_Of (Formal, Loc)),
                     List => Stmts);
               end if;

               Add_Invariant_Access_Checks (Formal);

               --  Note: we used to add predicate checks for OUT and IN OUT
               --  formals here, but that was misguided, since such checks are
               --  performed on the caller side, based on the predicate of the
               --  actual, rather than the predicate of the formal.

            end if;

            Next_Formal (Formal);
         end loop;
      end Add_Invariant_And_Predicate_Checks;

      -------------------------
      -- Append_Enabled_Item --
      -------------------------

      procedure Append_Enabled_Item (Item : Node_Id; List : in out List_Id) is
      begin
         --  Do not chain ignored or disabled pragmas

         if Nkind (Item) = N_Pragma
           and then (Is_Ignored (Item) or else Is_Disabled (Item))
         then
            null;

         --  Otherwise, add the item

         else
            if No (List) then
               List := New_List;
            end if;

            --  If the pragma is a conjunct in a composite postcondition, it
            --  has been processed in reverse order. In the postcondition body
            --  it must appear before the others.

            if Nkind (Item) = N_Pragma
              and then From_Aspect_Specification (Item)
              and then Split_PPC (Item)
            then
               Prepend (Item, List);
            else
               Append (Item, List);
            end if;
         end if;
      end Append_Enabled_Item;

      ------------------------------------
      -- Build_Postconditions_Procedure --
      ------------------------------------

      procedure Build_Postconditions_Procedure
        (Subp_Id : Entity_Id;
         Stmts   : List_Id;
         Result  : Entity_Id)
      is
         Loc       : constant Source_Ptr := Sloc (Body_Decl);
         Params    : List_Id := No_List;
         Proc_Bod  : Node_Id;
         Proc_Decl : Node_Id;
         Proc_Id   : Entity_Id;
         Proc_Spec : Node_Id;

      begin
         --  Nothing to do if there are no actions to check on exit

         if No (Stmts) then
            return;
         end if;

         Proc_Id := Make_Defining_Identifier (Loc, Name_uPostconditions);
         Set_Debug_Info_Needed   (Proc_Id);
         Set_Postconditions_Proc (Subp_Id, Proc_Id);

         --  Force the front-end inlining of _Postconditions when generating C
         --  code, since its body may have references to itypes defined in the
         --  enclosing subprogram, which would cause problems for unnesting
         --  routines in the absence of inlining.

         if Modify_Tree_For_C then
            Set_Has_Pragma_Inline        (Proc_Id);
            Set_Has_Pragma_Inline_Always (Proc_Id);
            Set_Is_Inlined               (Proc_Id);
         end if;

         --  The related subprogram is a function: create the specification of
         --  parameter _Result.

         if Present (Result) then
            Params := New_List (
              Make_Parameter_Specification (Loc,
                Defining_Identifier => Result,
                Parameter_Type      =>
                  New_Occurrence_Of (Etype (Result), Loc)));
         end if;

         Proc_Spec :=
           Make_Procedure_Specification (Loc,
             Defining_Unit_Name       => Proc_Id,
             Parameter_Specifications => Params);

         Proc_Decl := Make_Subprogram_Declaration (Loc, Proc_Spec);

         --  Insert _Postconditions before the first source declaration of the
         --  body. This ensures that the body will not cause any premature
         --  freezing, as it may mention types:

         --    procedure Proc (Obj : Array_Typ) is
         --       procedure _postconditions is
         --       begin
         --          ... Obj ...
         --       end _postconditions;

         --       subtype T is Array_Typ (Obj'First (1) .. Obj'Last (1));
         --    begin

         --  In the example above, Obj is of type T but the incorrect placement
         --  of _Postconditions will cause a crash in gigi due to an out-of-
         --  order reference. The body of _Postconditions must be placed after
         --  the declaration of Temp to preserve correct visibility.

         Insert_Before_First_Source_Declaration
           (Proc_Decl, Declarations (Body_Decl));
         Analyze (Proc_Decl);

         --  Set an explicit End_Label to override the sloc of the implicit
         --  RETURN statement, and prevent it from inheriting the sloc of one
         --  the postconditions: this would cause confusing debug info to be
         --  produced, interfering with coverage-analysis tools.

         Proc_Bod :=
           Make_Subprogram_Body (Loc,
             Specification              =>
               Copy_Subprogram_Spec (Proc_Spec),
             Declarations               => Empty_List,
             Handled_Statement_Sequence =>
               Make_Handled_Sequence_Of_Statements (Loc,
                 Statements => Stmts,
                 End_Label  => Make_Identifier (Loc, Chars (Proc_Id))));

         Insert_After_And_Analyze (Proc_Decl, Proc_Bod);
      end Build_Postconditions_Procedure;

      ----------------------------
      -- Process_Contract_Cases --
      ----------------------------

      procedure Process_Contract_Cases (Stmts : in out List_Id) is
         procedure Process_Contract_Cases_For (Subp_Id : Entity_Id);
         --  Process pragma Contract_Cases for subprogram Subp_Id

         --------------------------------
         -- Process_Contract_Cases_For --
         --------------------------------

         procedure Process_Contract_Cases_For (Subp_Id : Entity_Id) is
            Items : constant Node_Id := Contract (Subp_Id);
            Prag  : Node_Id;

         begin
            if Present (Items) then
               Prag := Contract_Test_Cases (Items);
               while Present (Prag) loop
                  if Is_Checked (Prag) then
                     if Pragma_Name (Prag) = Name_Contract_Cases then
                        Expand_Pragma_Contract_Cases
                          (CCs     => Prag,
                           Subp_Id => Subp_Id,
                           Decls   => Declarations (Body_Decl),
                           Stmts   => Stmts);

                     elsif Pragma_Name (Prag) = Name_Subprogram_Variant then
                        Expand_Pragma_Subprogram_Variant
                          (Prag       => Prag,
                           Subp_Id    => Subp_Id,
                           Body_Decls => Declarations (Body_Decl));
                     end if;
                  end if;

                  Prag := Next_Pragma (Prag);
               end loop;
            end if;
         end Process_Contract_Cases_For;

         pragma Unmodified (Stmts);
         --  Stmts is passed as IN OUT to signal that the list can be updated,
         --  even if the corresponding integer value representing the list does
         --  not change.

      --  Start of processing for Process_Contract_Cases

      begin
         Process_Contract_Cases_For (Body_Id);

         if Present (Spec_Id) then
            Process_Contract_Cases_For (Spec_Id);
         end if;
      end Process_Contract_Cases;

      ----------------------------
      -- Process_Postconditions --
      ----------------------------

      procedure Process_Postconditions (Stmts : in out List_Id) is
         procedure Process_Body_Postconditions (Post_Nam : Name_Id);
         --  Collect all [refined] postconditions of a specific kind denoted
         --  by Post_Nam that belong to the body, and generate pragma Check
         --  equivalents in list Stmts.

         procedure Process_Spec_Postconditions;
         --  Collect all [inherited] postconditions of the spec, and generate
         --  pragma Check equivalents in list Stmts.

         ---------------------------------
         -- Process_Body_Postconditions --
         ---------------------------------

         procedure Process_Body_Postconditions (Post_Nam : Name_Id) is
            Items     : constant Node_Id := Contract (Body_Id);
            Unit_Decl : constant Node_Id := Parent (Body_Decl);
            Decl      : Node_Id;
            Prag      : Node_Id;

         begin
            --  Process the contract

            if Present (Items) then
               Prag := Pre_Post_Conditions (Items);
               while Present (Prag) loop
                  if Pragma_Name (Prag) = Post_Nam
                    and then Is_Checked (Prag)
                  then
                     Append_Enabled_Item
                       (Item => Build_Pragma_Check_Equivalent (Prag),
                        List => Stmts);
                  end if;

                  Prag := Next_Pragma (Prag);
               end loop;
            end if;

            --  The subprogram body being processed is actually the proper body
            --  of a stub with a corresponding spec. The subprogram stub may
            --  carry a postcondition pragma, in which case it must be taken
            --  into account. The pragma appears after the stub.

            if Present (Spec_Id) and then Nkind (Unit_Decl) = N_Subunit then
               Decl := Next (Corresponding_Stub (Unit_Decl));
               while Present (Decl) loop

                  --  Note that non-matching pragmas are skipped

                  if Nkind (Decl) = N_Pragma then
                     if Pragma_Name (Decl) = Post_Nam
                       and then Is_Checked (Decl)
                     then
                        Append_Enabled_Item
                          (Item => Build_Pragma_Check_Equivalent (Decl),
                           List => Stmts);
                     end if;

                  --  Skip internally generated code

                  elsif not Comes_From_Source (Decl) then
                     null;

                  --  Postcondition pragmas are usually grouped together. There
                  --  is no need to inspect the whole declarative list.

                  else
                     exit;
                  end if;

                  Next (Decl);
               end loop;
            end if;
         end Process_Body_Postconditions;

         ---------------------------------
         -- Process_Spec_Postconditions --
         ---------------------------------

         procedure Process_Spec_Postconditions is
            Subps   : constant Subprogram_List :=
                        Inherited_Subprograms (Spec_Id);
            Item    : Node_Id;
            Items   : Node_Id;
            Prag    : Node_Id;
            Subp_Id : Entity_Id;

         begin
            --  Process the contract

            Items := Contract (Spec_Id);

            if Present (Items) then
               Prag := Pre_Post_Conditions (Items);
               while Present (Prag) loop
                  if Pragma_Name (Prag) = Name_Postcondition
                    and then Is_Checked (Prag)
                  then
                     Append_Enabled_Item
                       (Item => Build_Pragma_Check_Equivalent (Prag),
                        List => Stmts);
                  end if;

                  Prag := Next_Pragma (Prag);
               end loop;
            end if;

            --  Process the contracts of all inherited subprograms, looking for
            --  class-wide postconditions.

            for Index in Subps'Range loop
               Subp_Id := Subps (Index);
               Items   := Contract (Subp_Id);

               if Present (Items) then
                  Prag := Pre_Post_Conditions (Items);
                  while Present (Prag) loop
                     if Pragma_Name (Prag) = Name_Postcondition
                       and then Class_Present (Prag)
                     then
                        Item :=
                          Build_Pragma_Check_Equivalent
                            (Prag     => Prag,
                             Subp_Id  => Spec_Id,
                             Inher_Id => Subp_Id);

                        --  The pragma Check equivalent of the class-wide
                        --  postcondition is still created even though the
                        --  pragma may be ignored because the equivalent
                        --  performs semantic checks.

                        if Is_Checked (Prag) then
                           Append_Enabled_Item (Item, Stmts);
                        end if;
                     end if;

                     Prag := Next_Pragma (Prag);
                  end loop;
               end if;
            end loop;
         end Process_Spec_Postconditions;

         pragma Unmodified (Stmts);
         --  Stmts is passed as IN OUT to signal that the list can be updated,
         --  even if the corresponding integer value representing the list does
         --  not change.

      --  Start of processing for Process_Postconditions

      begin
         --  The processing of postconditions is done in reverse order (body
         --  first) to ensure the following arrangement:

         --    <refined postconditions from body>
         --    <postconditions from body>
         --    <postconditions from spec>
         --    <inherited postconditions>

         Process_Body_Postconditions (Name_Refined_Post);
         Process_Body_Postconditions (Name_Postcondition);

         if Present (Spec_Id) then
            Process_Spec_Postconditions;
         end if;
      end Process_Postconditions;

      ---------------------------
      -- Process_Preconditions --
      ---------------------------

      procedure Process_Preconditions is
         Class_Pre : Node_Id := Empty;
         --  The sole [inherited] class-wide precondition pragma that applies
         --  to the subprogram.

         Insert_Node : Node_Id := Empty;
         --  The insertion node after which all pragma Check equivalents are
         --  inserted.

         function Is_Prologue_Renaming (Decl : Node_Id) return Boolean;
         --  Determine whether arbitrary declaration Decl denotes a renaming of
         --  a discriminant or protection field _object.

         procedure Merge_Preconditions (From : Node_Id; Into : Node_Id);
         --  Merge two class-wide preconditions by "or else"-ing them. The
         --  changes are accumulated in parameter Into. Update the error
         --  message of Into.

         procedure Prepend_To_Decls (Item : Node_Id);
         --  Prepend a single item to the declarations of the subprogram body

         procedure Prepend_To_Decls_Or_Save (Prag : Node_Id);
         --  Save a class-wide precondition into Class_Pre, or prepend a normal
         --  precondition to the declarations of the body and analyze it.

         procedure Process_Inherited_Preconditions;
         --  Collect all inherited class-wide preconditions and merge them into
         --  one big precondition to be evaluated as pragma Check.

         procedure Process_Preconditions_For (Subp_Id : Entity_Id);
         --  Collect all preconditions of subprogram Subp_Id and prepend their
         --  pragma Check equivalents to the declarations of the body.

         --------------------------
         -- Is_Prologue_Renaming --
         --------------------------

         function Is_Prologue_Renaming (Decl : Node_Id) return Boolean is
            Nam  : Node_Id;
            Obj  : Entity_Id;
            Pref : Node_Id;
            Sel  : Node_Id;

         begin
            if Nkind (Decl) = N_Object_Renaming_Declaration then
               Obj := Defining_Entity (Decl);
               Nam := Name (Decl);

               if Nkind (Nam) = N_Selected_Component then
                  Pref := Prefix (Nam);
                  Sel  := Selector_Name (Nam);

                  --  A discriminant renaming appears as
                  --    Discr : constant ... := Prefix.Discr;

                  if Ekind (Obj) = E_Constant
                    and then Is_Entity_Name (Sel)
                    and then Present (Entity (Sel))
                    and then Ekind (Entity (Sel)) = E_Discriminant
                  then
                     return True;

                  --  A protection field renaming appears as
                  --    Prot : ... := _object._object;

                  --  A renamed private component is just a component of
                  --  _object, with an arbitrary name.

                  elsif Ekind (Obj) in E_Variable | E_Constant
                    and then Nkind (Pref) = N_Identifier
                    and then Chars (Pref) = Name_uObject
                    and then Nkind (Sel) = N_Identifier
                  then
                     return True;
                  end if;
               end if;
            end if;

            return False;
         end Is_Prologue_Renaming;

         -------------------------
         -- Merge_Preconditions --
         -------------------------

         procedure Merge_Preconditions (From : Node_Id; Into : Node_Id) is
            function Expression_Arg (Prag : Node_Id) return Node_Id;
            --  Return the boolean expression argument of a precondition while
            --  updating its parentheses count for the subsequent merge.

            function Message_Arg (Prag : Node_Id) return Node_Id;
            --  Return the message argument of a precondition

            --------------------
            -- Expression_Arg --
            --------------------

            function Expression_Arg (Prag : Node_Id) return Node_Id is
               Args : constant List_Id := Pragma_Argument_Associations (Prag);
               Arg  : constant Node_Id := Get_Pragma_Arg (Next (First (Args)));

            begin
               if Paren_Count (Arg) = 0 then
                  Set_Paren_Count (Arg, 1);
               end if;

               return Arg;
            end Expression_Arg;

            -----------------
            -- Message_Arg --
            -----------------

            function Message_Arg (Prag : Node_Id) return Node_Id is
               Args : constant List_Id := Pragma_Argument_Associations (Prag);
            begin
               return Get_Pragma_Arg (Last (Args));
            end Message_Arg;

            --  Local variables

            From_Expr : constant Node_Id := Expression_Arg (From);
            From_Msg  : constant Node_Id := Message_Arg    (From);
            Into_Expr : constant Node_Id := Expression_Arg (Into);
            Into_Msg  : constant Node_Id := Message_Arg    (Into);
            Loc       : constant Source_Ptr := Sloc (Into);

         --  Start of processing for Merge_Preconditions

         begin
            --  Merge the two preconditions by "or else"-ing them

            Rewrite (Into_Expr,
              Make_Or_Else (Loc,
                Right_Opnd => Relocate_Node (Into_Expr),
                Left_Opnd  => From_Expr));

            --  Merge the two error messages to produce a single message of the
            --  form:

            --    failed precondition from ...
            --      also failed inherited precondition from ...

            if not Exception_Locations_Suppressed then
               Start_String (Strval (Into_Msg));
               Store_String_Char (ASCII.LF);
               Store_String_Chars ("  also ");
               Store_String_Chars (Strval (From_Msg));

               Set_Strval (Into_Msg, End_String);
            end if;
         end Merge_Preconditions;

         ----------------------
         -- Prepend_To_Decls --
         ----------------------

         procedure Prepend_To_Decls (Item : Node_Id) is
            Decls : List_Id;

         begin
            Decls := Declarations (Body_Decl);

            --  Ensure that the body has a declarative list

            if No (Decls) then
               Decls := New_List;
               Set_Declarations (Body_Decl, Decls);
            end if;

            Prepend_To (Decls, Item);
         end Prepend_To_Decls;

         ------------------------------
         -- Prepend_To_Decls_Or_Save --
         ------------------------------

         procedure Prepend_To_Decls_Or_Save (Prag : Node_Id) is
            Check_Prag : Node_Id;

         begin
            Check_Prag := Build_Pragma_Check_Equivalent (Prag);

            --  Save the sole class-wide precondition (if any) for the next
            --  step, where it will be merged with inherited preconditions.

            if Class_Present (Prag) then
               pragma Assert (No (Class_Pre));
               Class_Pre := Check_Prag;

            --  Accumulate the corresponding Check pragmas at the top of the
            --  declarations. Prepending the items ensures that they will be
            --  evaluated in their original order.

            else
               if Present (Insert_Node) then
                  Insert_After (Insert_Node, Check_Prag);
               else
                  Prepend_To_Decls (Check_Prag);
               end if;

               Analyze (Check_Prag);
            end if;
         end Prepend_To_Decls_Or_Save;

         -------------------------------------
         -- Process_Inherited_Preconditions --
         -------------------------------------

         procedure Process_Inherited_Preconditions is
            Subps : constant Subprogram_List :=
                      Inherited_Subprograms (Spec_Id);

            Item    : Node_Id;
            Items   : Node_Id;
            Prag    : Node_Id;
            Subp_Id : Entity_Id;

         begin
            --  Process the contracts of all inherited subprograms, looking for
            --  class-wide preconditions.

            for Index in Subps'Range loop
               Subp_Id := Subps (Index);
               Items   := Contract (Subp_Id);

               if Present (Items) then
                  Prag := Pre_Post_Conditions (Items);
                  while Present (Prag) loop
                     if Pragma_Name (Prag) = Name_Precondition
                       and then Class_Present (Prag)
                     then
                        Item :=
                          Build_Pragma_Check_Equivalent
                            (Prag     => Prag,
                             Subp_Id  => Spec_Id,
                             Inher_Id => Subp_Id);

                        --  The pragma Check equivalent of the class-wide
                        --  precondition is still created even though the
                        --  pragma may be ignored because the equivalent
                        --  performs semantic checks.

                        if Is_Checked (Prag) then

                           --  The spec of an inherited subprogram already
                           --  yielded a class-wide precondition. Merge the
                           --  existing precondition with the current one
                           --  using "or else".

                           if Present (Class_Pre) then
                              Merge_Preconditions (Item, Class_Pre);
                           else
                              Class_Pre := Item;
                           end if;
                        end if;
                     end if;

                     Prag := Next_Pragma (Prag);
                  end loop;
               end if;
            end loop;

            --  Add the merged class-wide preconditions

            if Present (Class_Pre) then
               Prepend_To_Decls (Class_Pre);
               Analyze (Class_Pre);
            end if;
         end Process_Inherited_Preconditions;

         -------------------------------
         -- Process_Preconditions_For --
         -------------------------------

         procedure Process_Preconditions_For (Subp_Id : Entity_Id) is
            Items     : constant Node_Id := Contract (Subp_Id);
            Subp_Decl : constant Node_Id := Unit_Declaration_Node (Subp_Id);
            Decl      : Node_Id;
            Freeze_T  : Boolean;
            Prag      : Node_Id;

         begin
            --  Process the contract. If the body is an expression function
            --  that is a completion, freeze types within, because this may
            --  not have been done yet, when the subprogram declaration and
            --  its completion by an expression function appear in distinct
            --  declarative lists of the same unit (visible and private).

            Freeze_T :=
              Was_Expression_Function (Body_Decl)
                and then Sloc (Body_Id) /= Sloc (Subp_Id)
                and then In_Same_Source_Unit (Body_Id, Subp_Id)
                and then List_Containing (Body_Decl) /=
                         List_Containing (Subp_Decl);

            if Present (Items) then
               Prag := Pre_Post_Conditions (Items);
               while Present (Prag) loop
                  if Pragma_Name (Prag) = Name_Precondition
                    and then Is_Checked (Prag)
                  then
                     if Freeze_T
                       and then Present (Corresponding_Aspect (Prag))
                     then
                        Freeze_Expr_Types
                          (Def_Id => Subp_Id,
                           Typ    => Standard_Boolean,
                           Expr   =>
                             Expression
                               (First (Pragma_Argument_Associations (Prag))),
                           N      => Body_Decl);
                     end if;

                     Prepend_To_Decls_Or_Save (Prag);
                  end if;

                  Prag := Next_Pragma (Prag);
               end loop;
            end if;

            --  The subprogram declaration being processed is actually a body
            --  stub. The stub may carry a precondition pragma, in which case
            --  it must be taken into account. The pragma appears after the
            --  stub.

            if Nkind (Subp_Decl) = N_Subprogram_Body_Stub then

               --  Inspect the declarations following the body stub

               Decl := Next (Subp_Decl);
               while Present (Decl) loop

                  --  Note that non-matching pragmas are skipped

                  if Nkind (Decl) = N_Pragma then
                     if Pragma_Name (Decl) = Name_Precondition
                       and then Is_Checked (Decl)
                     then
                        Prepend_To_Decls_Or_Save (Decl);
                     end if;

                  --  Skip internally generated code

                  elsif not Comes_From_Source (Decl) then
                     null;

                  --  Preconditions are usually grouped together. There is no
                  --  need to inspect the whole declarative list.

                  else
                     exit;
                  end if;

                  Next (Decl);
               end loop;
            end if;
         end Process_Preconditions_For;

         --  Local variables

         Decls : constant List_Id := Declarations (Body_Decl);
         Decl  : Node_Id;

      --  Start of processing for Process_Preconditions

      begin
         --  Find the proper insertion point for all pragma Check equivalents

         if Present (Decls) then
            Decl := First (Decls);
            while Present (Decl) loop

               --  First source declaration terminates the search, because all
               --  preconditions must be evaluated prior to it, by definition.

               if Comes_From_Source (Decl) then
                  exit;

               --  Certain internally generated object renamings such as those
               --  for discriminants and protection fields must be elaborated
               --  before the preconditions are evaluated, as their expressions
               --  may mention the discriminants. The renamings include those
               --  for private components so we need to find the last such.

               elsif Is_Prologue_Renaming (Decl) then
                  while Present (Next (Decl))
                    and then Is_Prologue_Renaming (Next (Decl))
                  loop
                     Next (Decl);
                  end loop;

                  Insert_Node := Decl;

               --  Otherwise the declaration does not come from source. This
               --  also terminates the search, because internal code may raise
               --  exceptions which should not preempt the preconditions.

               else
                  exit;
               end if;

               Next (Decl);
            end loop;
         end if;

         --  The processing of preconditions is done in reverse order (body
         --  first), because each pragma Check equivalent is inserted at the
         --  top of the declarations. This ensures that the final order is
         --  consistent with following diagram:

         --    <inherited preconditions>
         --    <preconditions from spec>
         --    <preconditions from body>

         Process_Preconditions_For (Body_Id);

         if Present (Spec_Id) then
            Process_Preconditions_For (Spec_Id);
            Process_Inherited_Preconditions;
         end if;
      end Process_Preconditions;

      --  Local variables

      Restore_Scope : Boolean := False;
      Result        : Entity_Id;
      Stmts         : List_Id := No_List;
      Subp_Id       : Entity_Id;

   --  Start of processing for Expand_Subprogram_Contract

   begin
      --  Obtain the entity of the initial declaration

      if Present (Spec_Id) then
         Subp_Id := Spec_Id;
      else
         Subp_Id := Body_Id;
      end if;

      --  Do not perform expansion activity when it is not needed

      if not Expander_Active then
         return;

      --  GNATprove does not need the executable semantics of a contract

      elsif GNATprove_Mode then
         return;

      --  The contract of a generic subprogram or one declared in a generic
      --  context is not expanded, as the corresponding instance will provide
      --  the executable semantics of the contract.

      elsif Is_Generic_Subprogram (Subp_Id) or else Inside_A_Generic then
         return;

      --  All subprograms carry a contract, but for some it is not significant
      --  and should not be processed. This is a small optimization.

      elsif not Has_Significant_Contract (Subp_Id) then
         return;

      --  The contract of an ignored Ghost subprogram does not need expansion,
      --  because the subprogram and all calls to it will be removed.

      elsif Is_Ignored_Ghost_Entity (Subp_Id) then
         return;

      --  Do not re-expand the same contract. This scenario occurs when a
      --  construct is rewritten into something else during its analysis
      --  (expression functions for instance).

      elsif Has_Expanded_Contract (Subp_Id) then
         return;
      end if;

      --  Prevent multiple expansion attempts of the same contract

      Set_Has_Expanded_Contract (Subp_Id);

      --  Ensure that the formal parameters are visible when expanding all
      --  contract items.

      if not In_Open_Scopes (Subp_Id) then
         Restore_Scope := True;
         Push_Scope (Subp_Id);

         if Is_Generic_Subprogram (Subp_Id) then
            Install_Generic_Formals (Subp_Id);
         else
            Install_Formals (Subp_Id);
         end if;
      end if;

      --  The expansion of a subprogram contract involves the creation of Check
      --  pragmas to verify the contract assertions of the spec and body in a
      --  particular order. The order is as follows:

      --    function Example (...) return ... is
      --       procedure _Postconditions (...) is
      --       begin
      --          <refined postconditions from body>
      --          <postconditions from body>
      --          <postconditions from spec>
      --          <inherited postconditions>
      --          <contract case consequences>
      --          <invariant check of function result>
      --          <invariant and predicate checks of parameters>
      --       end _Postconditions;

      --       <inherited preconditions>
      --       <preconditions from spec>
      --       <preconditions from body>
      --       <contract case conditions>

      --       <source declarations>
      --    begin
      --       <source statements>

      --       _Preconditions (Result);
      --       return Result;
      --    end Example;

      --  Routine _Postconditions holds all contract assertions that must be
      --  verified on exit from the related subprogram.

      --  Step 1: Handle all preconditions. This action must come before the
      --  processing of pragma Contract_Cases because the pragma prepends items
      --  to the body declarations.

      Process_Preconditions;

      --  Step 2: Handle all postconditions. This action must come before the
      --  processing of pragma Contract_Cases because the pragma appends items
      --  to list Stmts.

      Process_Postconditions (Stmts);

      --  Step 3: Handle pragma Contract_Cases. This action must come before
      --  the processing of invariants and predicates because those append
      --  items to list Stmts.

      Process_Contract_Cases (Stmts);

      --  Step 4: Apply invariant and predicate checks on a function result and
      --  all formals. The resulting checks are accumulated in list Stmts.

      Add_Invariant_And_Predicate_Checks (Subp_Id, Stmts, Result);

      --  Step 5: Construct procedure _Postconditions

      Build_Postconditions_Procedure (Subp_Id, Stmts, Result);

      if Restore_Scope then
         End_Scope;
      end if;
   end Expand_Subprogram_Contract;

   -------------------------------
   -- Freeze_Previous_Contracts --
   -------------------------------

   procedure Freeze_Previous_Contracts (Body_Decl : Node_Id) is
      function Causes_Contract_Freezing (N : Node_Id) return Boolean;
      pragma Inline (Causes_Contract_Freezing);
      --  Determine whether arbitrary node N causes contract freezing

      procedure Freeze_Contracts;
      pragma Inline (Freeze_Contracts);
      --  Freeze the contracts of all eligible constructs which precede body
      --  Body_Decl.

      procedure Freeze_Enclosing_Package_Body;
      pragma Inline (Freeze_Enclosing_Package_Body);
      --  Freeze the contract of the nearest package body (if any) which
      --  encloses body Body_Decl.

      ------------------------------
      -- Causes_Contract_Freezing --
      ------------------------------

      function Causes_Contract_Freezing (N : Node_Id) return Boolean is
      begin
         return Nkind (N) in
           N_Entry_Body      | N_Package_Body         | N_Protected_Body |
           N_Subprogram_Body | N_Subprogram_Body_Stub | N_Task_Body;
      end Causes_Contract_Freezing;

      ----------------------
      -- Freeze_Contracts --
      ----------------------

      procedure Freeze_Contracts is
         Body_Id : constant Entity_Id := Defining_Entity (Body_Decl);
         Decl    : Node_Id;

      begin
         --  Nothing to do when the body which causes freezing does not appear
         --  in a declarative list because there cannot possibly be constructs
         --  with contracts.

         if not Is_List_Member (Body_Decl) then
            return;
         end if;

         --  Inspect the declarations preceding the body, and freeze individual
         --  contracts of eligible constructs.

         Decl := Prev (Body_Decl);
         while Present (Decl) loop

            --  Stop the traversal when a preceding construct that causes
            --  freezing is encountered as there is no point in refreezing
            --  the already frozen constructs.

            if Causes_Contract_Freezing (Decl) then
               exit;

            --  Entry or subprogram declarations

            elsif Nkind (Decl) in N_Abstract_Subprogram_Declaration
                                | N_Entry_Declaration
                                | N_Generic_Subprogram_Declaration
                                | N_Subprogram_Declaration
            then
               Analyze_Entry_Or_Subprogram_Contract
                 (Subp_Id   => Defining_Entity (Decl),
                  Freeze_Id => Body_Id);

            --  Objects

            elsif Nkind (Decl) = N_Object_Declaration then
               Analyze_Object_Contract
                 (Obj_Id    => Defining_Entity (Decl),
                  Freeze_Id => Body_Id);

            --  Protected units

            elsif Nkind (Decl) in N_Protected_Type_Declaration
                                | N_Single_Protected_Declaration
            then
               Analyze_Protected_Contract (Defining_Entity (Decl));

            --  Subprogram body stubs

            elsif Nkind (Decl) = N_Subprogram_Body_Stub then
               Analyze_Subprogram_Body_Stub_Contract (Defining_Entity (Decl));

            --  Task units

            elsif Nkind (Decl) in N_Single_Task_Declaration
                                | N_Task_Type_Declaration
            then
               Analyze_Task_Contract (Defining_Entity (Decl));
            end if;

            if Nkind (Decl) in N_Full_Type_Declaration
                             | N_Private_Type_Declaration
                             | N_Task_Type_Declaration
                             | N_Protected_Type_Declaration
                             | N_Formal_Type_Declaration
            then
               Analyze_Type_Contract (Defining_Identifier (Decl));
            end if;

            Prev (Decl);
         end loop;
      end Freeze_Contracts;

      -----------------------------------
      -- Freeze_Enclosing_Package_Body --
      -----------------------------------

      procedure Freeze_Enclosing_Package_Body is
         Orig_Decl : constant Node_Id := Original_Node (Body_Decl);
         Par       : Node_Id;

      begin
         --  Climb the parent chain looking for an enclosing package body. Do
         --  not use the scope stack, because a body utilizes the entity of its
         --  corresponding spec.

         Par := Parent (Body_Decl);
         while Present (Par) loop
            if Nkind (Par) = N_Package_Body then
               Analyze_Package_Body_Contract
                 (Body_Id   => Defining_Entity (Par),
                  Freeze_Id => Defining_Entity (Body_Decl));

               exit;

            --  Do not look for an enclosing package body when the construct
            --  which causes freezing is a body generated for an expression
            --  function and it appears within a package spec. This ensures
            --  that the traversal will not reach too far up the parent chain
            --  and attempt to freeze a package body which must not be frozen.

            --    package body Enclosing_Body
            --      with Refined_State => (State => Var)
            --    is
            --       package Nested is
            --          type Some_Type is ...;
            --          function Cause_Freezing return ...;
            --       private
            --          function Cause_Freezing is (...);
            --       end Nested;
            --
            --       Var : Nested.Some_Type;

            elsif Nkind (Par) = N_Package_Declaration
              and then Nkind (Orig_Decl) = N_Expression_Function
            then
               exit;

            --  Prevent the search from going too far

            elsif Is_Body_Or_Package_Declaration (Par) then
               exit;
            end if;

            Par := Parent (Par);
         end loop;
      end Freeze_Enclosing_Package_Body;

      --  Local variables

      Body_Id : constant Entity_Id := Defining_Entity (Body_Decl);

   --  Start of processing for Freeze_Previous_Contracts

   begin
      pragma Assert (Causes_Contract_Freezing (Body_Decl));

      --  A body that is in the process of being inlined appears from source,
      --  but carries name _parent. Such a body does not cause freezing of
      --  contracts.

      if Chars (Body_Id) = Name_uParent then
         return;
      end if;

      Freeze_Enclosing_Package_Body;
      Freeze_Contracts;
   end Freeze_Previous_Contracts;

   ---------------------------------
   -- Inherit_Subprogram_Contract --
   ---------------------------------

   procedure Inherit_Subprogram_Contract
     (Subp      : Entity_Id;
      From_Subp : Entity_Id)
   is
      procedure Inherit_Pragma (Prag_Id : Pragma_Id);
      --  Propagate a pragma denoted by Prag_Id from From_Subp's contract to
      --  Subp's contract.

      --------------------
      -- Inherit_Pragma --
      --------------------

      procedure Inherit_Pragma (Prag_Id : Pragma_Id) is
         Prag     : constant Node_Id := Get_Pragma (From_Subp, Prag_Id);
         New_Prag : Node_Id;

      begin
         --  A pragma cannot be part of more than one First_Pragma/Next_Pragma
         --  chains, therefore the node must be replicated. The new pragma is
         --  flagged as inherited for distinction purposes.

         if Present (Prag) then
            New_Prag := New_Copy_Tree (Prag);
            Set_Is_Inherited_Pragma (New_Prag);

            Add_Contract_Item (New_Prag, Subp);
         end if;
      end Inherit_Pragma;

   --   Start of processing for Inherit_Subprogram_Contract

   begin
      --  Inheritance is carried out only when both entities are subprograms
      --  with contracts.

      if Is_Subprogram_Or_Generic_Subprogram (Subp)
        and then Is_Subprogram_Or_Generic_Subprogram (From_Subp)
        and then Present (Contract (From_Subp))
      then
         Inherit_Pragma (Pragma_Extensions_Visible);
      end if;
   end Inherit_Subprogram_Contract;

   -------------------------------------
   -- Instantiate_Subprogram_Contract --
   -------------------------------------

   procedure Instantiate_Subprogram_Contract (Templ : Node_Id; L : List_Id) is
      procedure Instantiate_Pragmas (First_Prag : Node_Id);
      --  Instantiate all contract-related source pragmas found in the list,
      --  starting with pragma First_Prag. Each instantiated pragma is added
      --  to list L.

      -------------------------
      -- Instantiate_Pragmas --
      -------------------------

      procedure Instantiate_Pragmas (First_Prag : Node_Id) is
         Inst_Prag : Node_Id;
         Prag      : Node_Id;

      begin
         Prag := First_Prag;
         while Present (Prag) loop
            if Is_Generic_Contract_Pragma (Prag) then
               Inst_Prag :=
                 Copy_Generic_Node (Prag, Empty, Instantiating => True);

               Set_Analyzed (Inst_Prag, False);
               Append_To (L, Inst_Prag);
            end if;

            Prag := Next_Pragma (Prag);
         end loop;
      end Instantiate_Pragmas;

      --  Local variables

      Items : constant Node_Id := Contract (Defining_Entity (Templ));

   --  Start of processing for Instantiate_Subprogram_Contract

   begin
      if Present (Items) then
         Instantiate_Pragmas (Pre_Post_Conditions (Items));
         Instantiate_Pragmas (Contract_Test_Cases (Items));
         Instantiate_Pragmas (Classifications     (Items));
      end if;
   end Instantiate_Subprogram_Contract;

   ----------------------------------------
   -- Save_Global_References_In_Contract --
   ----------------------------------------

   procedure Save_Global_References_In_Contract
     (Templ  : Node_Id;
      Gen_Id : Entity_Id)
   is
      procedure Save_Global_References_In_List (First_Prag : Node_Id);
      --  Save all global references in contract-related source pragmas found
      --  in the list, starting with pragma First_Prag.

      ------------------------------------
      -- Save_Global_References_In_List --
      ------------------------------------

      procedure Save_Global_References_In_List (First_Prag : Node_Id) is
         Prag : Node_Id;

      begin
         Prag := First_Prag;
         while Present (Prag) loop
            if Is_Generic_Contract_Pragma (Prag) then
               Save_Global_References (Prag);
            end if;

            Prag := Next_Pragma (Prag);
         end loop;
      end Save_Global_References_In_List;

      --  Local variables

      Items : constant Node_Id := Contract (Defining_Entity (Templ));

   --  Start of processing for Save_Global_References_In_Contract

   begin
      --  The entity of the analyzed generic copy must be on the scope stack
      --  to ensure proper detection of global references.

      Push_Scope (Gen_Id);

      if Permits_Aspect_Specifications (Templ)
        and then Has_Aspects (Templ)
      then
         Save_Global_References_In_Aspects (Templ);
      end if;

      if Present (Items) then
         Save_Global_References_In_List (Pre_Post_Conditions (Items));
         Save_Global_References_In_List (Contract_Test_Cases (Items));
         Save_Global_References_In_List (Classifications     (Items));
      end if;

      Pop_Scope;
   end Save_Global_References_In_Contract;

end Contracts;
