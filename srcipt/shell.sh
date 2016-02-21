ts(){

words=""
for word in $@; 
do
    words="$words$word "
done

curl -s \
        "http://fanyi.youdao.com/translate?smartresult=dict&smartresult=rule&smartresult=ugc&sessionFrom=dict.top" \
     -d \
	"type=AUTO& i=$words&doctype=json&xmlVersion=1.4&keyfrom=fanyi.web&ue=UTF-8&typoResult=true&flag=false" \
        | sed -r -n 's/.*tgt":"([^"]+)".*/\1/p' ;

return 0;
}
#http://hexlee.iteye.com/blog/1442506 comeformit
