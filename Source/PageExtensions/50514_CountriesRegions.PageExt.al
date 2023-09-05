pageextension 50514 CountriesRegions extends "Countries/Regions"
{
    layout
    {
        addafter("VAT Scheme")
        {
            field("Country Code for E Invoicing"; Rec."Country Code for E-Invoicing")
            {
                ToolTip = 'Specifies the value of the Country Code for E Invoicing field.';
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