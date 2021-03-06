//+------------------------------------------------------------------+
//|                                             Meta Diagnostics.mq4 |
//|                                            Credits to MellyForex |
//|                                        http://www.mellyforex.com |
//+------------------------------------------------------------------+
//#property copyright ""
//#property link      ""
#property description "EA used to capture order placement and cancellation response times and count server disconnects"

//--- input parameters
extern int     TestFrequency = 5;
extern string DiagnosticsURI = "http://10.5.212.167/MetaDiagnostics";

string         sessionStart = "";
string         sessionEnd = "";
datetime       lastTestOrderSent = 0;
int            TestFrequencySeconds;
int            magic = 4156434123;
int            minExecutionTime = 99999999;
int            maxExecutionTime = 0;
int            avExecutionTime = 0;
int            totalExecutionTime = 0;
int            totalTestTrades = 0;
int            totalConnectionFailures = 0;
int            connectionfailures = 0;

//+------------------------------------------------------------------+
//| expert initialization function                                   |
//+------------------------------------------------------------------+
int init() {
//----
   sessionStart = TimeToStr(TimeGMT(),TIME_DATE|TIME_SECONDS);
   if(!TestWebRequest())
     {
      MessageBox("The destination URL for the Latency EA is missing from the Expert Advisors tab of the Options window","Information",MB_ICONINFORMATION);
      return(INIT_FAILED);
     }
   TestFrequencySeconds = TestFrequency * 60;
//----
   return(0);
}

//+------------------------------------------------------------------+
//| expert deinitialization function                                 |
//+------------------------------------------------------------------+
int deinit() {
//----
   sessionEnd = TimeToStr(TimeGMT(),TIME_DATE|TIME_SECONDS);
   Print("deinit: Session Started: ", sessionStart, ", Session Ended: ", sessionEnd, ", Total Connection Failures: ", totalConnectionFailures);
   Comment("");   
//----
   return(0);
}

//+------------------------------------------------------------------+
//| expert start function                                            |
//+------------------------------------------------------------------+
int start() {
//----
   int openTicket = openTestOrderTicket();
   if(openTicket > 0)  closeTestOrder(openTicket);
   string text = "The Latency EA is sending test orders at "+TestFrequency+" minute intervals\n";
   if(minExecutionTime < 99999999)  {
      text = text + "Maximum Latency = "+maxExecutionTime+" milliseconds\n";
      text = text + "Minimum Latency = "+minExecutionTime+" milliseconds\n";
      text = text + "Average Latency = "+avExecutionTime+" milliseconds";
      }
   if(TimeCurrent() - lastTestOrderSent < TestFrequencySeconds)  {
      Comment(text);
      return(0);
      }
   if(openTicket == 0)  openTestOrder();

   //----
   return(0);
}

//+------------------------------------------------------------------+
//| function to test web url                                         |
//+------------------------------------------------------------------+
bool TestWebRequest() {
   string cookie=NULL,headers;
   char post[],result[];
   int res;

   ResetLastError();
   int timeout=5000; //--- timeout less than 1000 (1 sec.) is not sufficient for slow Internet speed
   res=WebRequest("GET",DiagnosticsURI,cookie,NULL,timeout,post,0,result,headers);
   if(res==-1) return(false);
   return(true);
}

//+------------------------------------------------------------------+
//| function to open a test order                                    |
//+------------------------------------------------------------------+  
void openTestOrder()  {
   int ticket=0; 
   int err=0; 
   int c = 0;
   int attempts = 20;
   double testOrderPrice = 1 / MathPow(10, Digits);
   double size = MarketInfo(Symbol(),MODE_MINLOT);

   while(ticket <= 0 && c < attempts){ 
      int xyz = 1;  //if the waiting time is exceeded (-1 is returned), let's recheck every 15 secs
      while(xyz == 1){ 
            if( !IsTradeAllowed() ) {
            Sleep(15000);
            c++;
            Print("A Trade Context delay prevented the Latency EA from opening a test order at attempt #"+c);
            continue;
            }
         if( IsTradeAllowed() ) break;
         if(c >= attempts)  {Alert("Trade attempts on "+Symbol()+" maxed at "+attempts); return;}
        }
            
   int startOrderTimestamp = GetTickCount();
   int elapsed = 0;
   ticket = OrderSend(Symbol(), OP_BUYLIMIT, size, NormalizeDouble(testOrderPrice, Digits), 0, 0, 0, "Latency EA", magic, 0, CLR_NONE);
   elapsed = GetTickCount() - startOrderTimestamp; 

   if (ticket > 0) {
      Print("It took "+elapsed+" milliseconds to open test LIMIT BUY ticket #"+ticket);
      if(elapsed < minExecutionTime)  minExecutionTime = elapsed;
      if(elapsed > maxExecutionTime)  maxExecutionTime = elapsed;
      totalExecutionTime += elapsed;
      totalTestTrades ++;
      avExecutionTime = totalExecutionTime / totalTestTrades;
      
      //This will report twice as the order is closed immediately after being opened.
      //So capture only after the order is closed.
      //ReportLatency (minExecutionTime, maxExecutionTime, avExecutionTime, elapsed);
      
      return;
   }
               
   if(ticket < 0)  {
      Print("A LIMIT BUY order send failed with error #", GetLastError());
      return;
      }
   }
}

//+------------------------------------------------------------------+
//| function to close a test order                                   |
//+------------------------------------------------------------------+
void closeTestOrder(int ticket)  {
   int startOrderTimestamp = GetTickCount();
   int elapsed = 0;
   bool success = OrderDelete(ticket, CLR_NONE);
   elapsed = GetTickCount() - startOrderTimestamp; 
   
   if(success)  {
      Print("It took "+elapsed+" milliseconds to close test LIMIT BUY ticket #"+ticket);
      if(elapsed < minExecutionTime)  minExecutionTime = elapsed;
      if(elapsed > maxExecutionTime)  maxExecutionTime = elapsed;
      totalExecutionTime += elapsed;
      totalTestTrades ++;
      avExecutionTime = totalExecutionTime / totalTestTrades;
      lastTestOrderSent = TimeCurrent();
      
      ReportLatency (minExecutionTime, maxExecutionTime, avExecutionTime, elapsed);
      
      return;
      }
      
   return;
}

int openTestOrderTicket()  {
   int Total = OrdersTotal();
   int ret = 0;
   for (int i = 0; i < Total; i ++) {
      OrderSelect(i, SELECT_BY_POS, MODE_TRADES);
      if(OrderSymbol() == Symbol() && OrderMagicNumber() == magic )  {
         ret = OrderTicket();
      }
   }
   
   return(ret);
}

//+------------------------------------------------------------------+
//| function to send diagnostics to remote web service               |
//+------------------------------------------------------------------+
void ReportLatency(int min, int max, int avg, int last)  {
   string cookie=NULL; //,headers;
   char post[],result[];
   string res;
   int timeout=5000; //--- Timeout below 1000 (1 sec.) is not enough for slow Internet connection
    
   if (IsConnected())
   {
      Print("Submitting diagnostics");
      string AcctNo = AccountNumber();
      //string str="AccountNumber="+AcctNo+"&Latency="+elapsed;
      string str="AccountNumber=" + AcctNo + ";Time=" + TimeToStr(TimeGMT(),TIME_DATE|TIME_SECONDS) + ";Min=" + min + ";Max=" + max + ";Avg=" + avg + ";Last=" + last + ";Failures=" + connectionfailures;
      char   data[];
      ArrayResize(data,StringToCharArray(str,data,0,WHOLE_ARRAY,CP_UTF8)-1);  
      
      res=WebRequest("POST",DiagnosticsURI,NULL,0,data,data,str);
      if(res==-1)
      {
         Print("Failed to submit diagnostics. Error code: ",GetLastError());
      }
      else
      {
         Print("Diagnostics submitted succesfully");
      }  
   }
   else
   {
      Print("Unable to submit diagnostics: not connected");
      totalConnectionFailures += 1;
      connectionfailures += 1;
   }
   return;
}