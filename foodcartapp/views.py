import json

from django.views.decorators.csrf import csrf_exempt
from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status
from django.http import JsonResponse
from django.templatetags.static import static
from .models import Order, OrderItem


from .models import Product


def banners_list_api(request):
    # FIXME move data to db?
    return JsonResponse([
        {
            'title': 'Burger',
            'src': static('burger.jpg'),
            'text': 'Tasty Burger at your door step',
        },
        {
            'title': 'Spices',
            'src': static('food.jpg'),
            'text': 'All Cuisines',
        },
        {
            'title': 'New York',
            'src': static('tasty.jpg'),
            'text': 'Food is incomplete without a tasty dessert',
        }
    ], safe=False, json_dumps_params={
        'ensure_ascii': False,
        'indent': 4,
    })


def product_list_api(request):
    products = Product.objects.select_related('category').available()

    dumped_products = []
    for product in products:
        dumped_product = {
            'id': product.id,
            'name': product.name,
            'price': product.price,
            'special_status': product.special_status,
            'description': product.description,
            'category': {
                'id': product.category.id,
                'name': product.category.name,
            } if product.category else None,
            'image': product.image.url,
            'restaurant': {
                'id': product.id,
                'name': product.name,
            }
        }
        dumped_products.append(dumped_product)
    return JsonResponse(dumped_products, safe=False, json_dumps_params={
        'ensure_ascii': False,
        'indent': 4,
    })


@api_view(['POST'])
@csrf_exempt
def register_order(request):
    recieved_submission = request.data

    print("Получено для заказа (DRF):")
    print(recieved_submission)

    try:
        products_details_list = recieved_submission['products']

        if products_details_list is None:
            return Response(
                {'products': ['Это поле не может быть пустым (null).']},
                status=status.HTTP_400_BAD_REQUEST
            )

        if not isinstance(products_details_list, list):
            error_message = f"Ожидался list со значениями, но был получен '{type(products_details_list).__name__}'."
            return Response(
                {'products': [error_message]},
                status=status.HTTP_400_BAD_REQUEST
            )
        if not products_details_list:
            return Response(
                {'products': ['Этот список не может быть пустым.']},
                status=status.HTTP_400_BAD_REQUEST
            )
    except KeyError:
        return Response(
            {'products': ['Обязательное поле.']},
            status=status.HTTP_400_BAD_REQUEST
        )


    new_order_record = Order.objects.create(
        client_name = recieved_submission.get('firstname'),
        surname = recieved_submission.get('lastname'),
        phone = recieved_submission.get('phonenumber'),
        delivery_address = recieved_submission.get('address')
    )

    product_details = recieved_submission.get('products', [])

    for product in product_details:
        product_id = product.get('product')
        quantity = product.get('quantity')

        product_object = Product.objects.get(id=product_id)

        OrderItem.objects.create(
            order=new_order_record,
            product=product_object,
            quantity=quantity
        )

    return Response({'order_id': new_order_record.id}, status=status.HTTP_201_CREATED)



