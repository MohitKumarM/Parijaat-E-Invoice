pageextension 50500 UnitsOfMeasure extends "Units of Measure"
{
    layout
    {
        addafter("International Standard Code")
        {
            field("UOM For E Invoicing"; Rec."UOM For E Invoicing")
            {
                ToolTip = 'Specifies the value of the UOM For E Invoicing field.';
                ApplicationArea = All;
            }
        }
    }


    actions
    {
        // Add changes to page actions here
    }

    var
        myInt: Integer;
}