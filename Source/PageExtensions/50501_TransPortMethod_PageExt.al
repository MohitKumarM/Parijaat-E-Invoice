pageextension 50510 pageextension50510 extends "Transport Methods"
{
    layout
    {
        addafter(Description)
        {
            field("Transportation Mode"; Rec."Transportation Mode")
            {
                ApplicationArea = all;
                Editable = true;
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